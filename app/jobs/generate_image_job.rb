class GenerateImageJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation_id:, **) { "generate-image-#{conversation_id}" }, duration: 2.minutes

  def perform(conversation_id:, user_id:, prompt:, tool_call_id:)
    conversation = Conversation.find_by(id: conversation_id)
    user = User.find_by(id: user_id)

    unless conversation && user
      Rails.logger.warn "GenerateImageJob skipped: conversation or user missing (conversation_id=#{conversation_id}, user_id=#{user_id})"
      return
    end

    tempfile = nil
    begin
      tempfile = ImageGenerationService.generate(user: user, prompt: prompt, conversation: conversation)
      attach_image_tool_message(conversation: conversation, tempfile: tempfile, tool_call_id: tool_call_id)
    rescue StandardError => e
      Rails.logger.error "GenerateImageJob error: #{e.message}"
      create_tool_message(conversation: conversation, tool_call_id: tool_call_id, content: "Image generation failed: #{e.message}")
    ensure
      # Close the Tempfile after attachment to free resources.
      if tempfile
        tempfile.close if tempfile.respond_to?(:close) && !tempfile.closed?
        tempfile.unlink if tempfile.respond_to?(:unlink) && tempfile.path && File.exist?(tempfile.path)
      end
    end
  end

  private

  def attach_image_tool_message(conversation:, tempfile:, tool_call_id:)
    unless tempfile.is_a?(Tempfile)
      raise StandardError, "Image generation did not return a valid Tempfile."
    end

    # Create the tool message and attach image within a transaction
    # so that when the transaction commits, the image is attached
    # and the broadcast_created callback (which runs after commit)
    # sees the image and broadcasts the message.
    Message.transaction do
      tool_message = Message.create!(
        conversation: conversation,
        role: "tool",
        content: "Image generation done.",
        tool_call_id: tool_call_id
      )

      filename = "generated-#{Time.current.to_i}.jpg"

      image = tool_message.images.build
      image.file.attach(
        io: tempfile,
        filename: filename,
        content_type: "image/jpeg"
      )
      image.save!
    end
  rescue StandardError => e
    raise StandardError, "Error saving generated image: #{e.message}"
  end

  def create_tool_message(conversation:, tool_call_id:, content:)
    Message.create!(
      conversation: conversation,
      role: "tool",
      content: content,
      tool_call_id: tool_call_id
    )
  end
end
