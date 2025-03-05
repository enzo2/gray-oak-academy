class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  self.implicit_order_column = "created_at" # just in case IDs get out of order somehow

  enum :role, { system: "system", assistant: "assistant", user: "user" }, prefix: true

  belongs_to :conversation
  has_many :images, dependent: :destroy # Message content field contains text. Images are kept separately.

  after_create_commit -> { broadcast_created; check_context_limit }
  after_update_commit -> { broadcast_updated }

  def broadcast_created
    Rails.logger.debug "Broadcasting created message: #{self.inspect}"
    broadcast_append_to(  # docs recommend _later_to, but this causes view to render first, putting the placeholder out of order
      "#{dom_id(conversation)}",
      partial: "messages/message",
      locals: { message: self },
      scroll_to: true,
      target: "#{dom_id(conversation)}"
    )

    # Remove any temporary new message placeholder
    broadcast_remove_to("#{dom_id(conversation)}", target: "new_message")
  end

  def broadcast_updated
    Rails.logger.debug "Broadcasting updated message: #{self.inspect}"
    broadcast_replace_later_to(
      "#{dom_id(conversation)}",
      partial: "messages/message",
      locals: { message: self },
      # scroll_to: true,
      target: dom_id(self)
    )
  end

  # Return content in JSON format with base64 images for LLM APIs.
  def content_with_images
    return content if images.empty?

    content_json = [ { "type": "text", "text": content } ]
    images.each do |image|
      content_json << { "type": "image_url", "image_url": { "url": image.image_for_LLM } }
    end
    content_json
  end

  # Deprecated now that images are added
  def self.for_completion(messages)
    # Remove the latest message if it's blank, since some LLM providers don't like blank messages
    if messages.last.content.blank?
      messages = messages[0...-1]
    end
    messages.map { |message| { role: message.role, content: message.content } }
  end

  # Format messages for the LLM api
  def self.for_completion_with_images(messages)
    # Remove the latest message if it's blank, since some LLM providers don't like blank messages
    if messages.last.content.blank?
      messages = messages[0...-1]
    end
    messages.map { |message| { role: message.role, content: message.content_with_images } }
  end

  private

  def check_context_limit
    return unless role_user? # Only run this check for user messages
    Rails.logger.debug "Checking context limit for message: #{self.inspect}"

    # Get the model's context limit
    llm = conversation.completions.last&.llm
    return unless llm

    context_limit = llm.context_length
    return unless context_limit

    # Check the threshold (model's context limit - 64,000)
    threshold = context_limit - 64000

    if conversation.total_prompt_tokens > threshold
      Rails.logger.warn("Conversation #{conversation.id} is approaching the context limit: #{conversation.total_prompt_tokens} / #{threshold}")
      # Display the flash warning
      Turbo::StreamsChannel.broadcast_update_to(
        "#{dom_id(conversation)}",
        target: "flash_bar",
        partial: "shared/flash",
        locals: { flash: { warning: "The conversation is approaching the token limit. Please notify the teacher to switch to a model with a larger limit." } }
      )

      # Send email to teacher/admin
      Rails.logger.debug "Sending email to admin for conversation: #{conversation.id}"
      ContextLimitMailer.notify_admin(conversation).deliver_later
    end
  end
end
