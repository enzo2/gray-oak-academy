class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  self.implicit_order_column = "created_at" # just in case IDs get out of order somehow

  enum :role, { system: "system", assistant: "assistant", user: "user", tool: "tool" }, prefix: true

  belongs_to :conversation
  has_many :images, dependent: :destroy # Message content field contains text. Images are kept separately.
  has_many :audios, dependent: :destroy # Audio is kept separately.

  before_create :ensure_text_present

  # Include broadcast logic in the model, since it's an inherent property of Messages that they will need to be viewed immediately.
  after_create_commit -> { broadcast_created; check_context_limit }
  after_update_commit -> { broadcast_updated }
  after_destroy_commit -> { broadcast_destroyed }

  def broadcast_created
    return if role_tool? # Don't broadcast tool messages, as they are only shown to the LLM.
    Rails.logger.debug "Broadcasting created message: #{self.inspect}"
    # Could change to broadcast_append_to (synchronous) if any issues with the assistant reply appearing before the user message
    broadcast_append_later_to(
      "#{dom_id(conversation)}",
      partial: "messages/message",
      target: "#{dom_id(conversation)}",
      locals: { message: self }
    )
    # Remove any temporary new message placeholder
    broadcast_remove_to("#{dom_id(conversation)}", target: "new_message") if role_assistant?
  end

  def broadcast_updated
    Rails.logger.debug "Broadcasting updated message: #{self.inspect}"
    # See https://github.com/hotwired/turbo-rails/issues/644
    # Replace only the message content using the inner_html of the rendered partial.
    html = ApplicationController.renderer_with_signed_in_user(conversation.user).render(partial: "messages/message_content", locals: { message: self })
    dom = Nokogiri::HTML.fragment(html)
    html = dom.at_css(":root").inner_html
    broadcast_update_to( # Don't use broadcast_update_later_to since jobs may be processed out of order and message stream will be janky/truncated.
      "#{dom_id(conversation)}",
      target: "#{dom_id(self)}_content",
      html: html
    )
  end

  def broadcast_destroyed
    Rails.logger.debug "Broadcasting destroyed message: #{self.inspect}"
    broadcast_remove_to("#{dom_id(conversation)}", target: dom_id(self))
    broadcast_remove_to("#{dom_id(conversation)}", target: "#{dom_id(self)}_buttons")
  end

  # Return content in JSON format with base64 images for LLM APIs.
  def content_with_images
    if images.empty?
      # OpenAI API accepts a string or array. Stick with the string for now.
      # return [{ "type": "text", "text": content }] if role_tool?
      # For other roles, just return the raw text string.
      return content
    end

    # If there are images, always return an array.
    content_json = [ { "type": "text", "text": content } ]
    images.each do |image|
      content_json << { "type": "image_url", "image_url": { "url": image.image_for_LLM } }
    end
    content_json
  end

  # Return content in JSON format with base64 images and audio for LLM APIs.
  def content_with_media
    base_content = content_with_images
    return base_content if audios.empty?

    if base_content.empty?
      # If base_content is empty, start with an empty array.
      content_json = []
    elsif base_content.is_a?(String)
      # If base_content is just a string (text only or empty), convert to array format since we'll be adding audio.
      content_json = [ { "type": "text", "text": base_content } ]
    else
      # Otherwise, it's already in the correct format.
      content_json = base_content
    end

    audios.each do |audio|
      audio_data = audio.base64_for_LLM
      content_json << { "type": "input_audio", "input_audio": audio_data } if audio_data
    end
    content_json
  end

  # Format messages for the LLM api
  def self.for_completion_with_media(messages:, audio: false)
    messages.map do |message|
      msg_hash = { role: message.role, content: audio ? message.content_with_media : message.content_with_images }
      msg_hash[:tool_call_id] = message.tool_call_id if message.role_tool? && message.respond_to?(:tool_call_id) && message.tool_call_id.present?
      msg_hash[:tool_calls] = message.tool_calls if message.role_assistant? && message.respond_to?(:tool_calls) && message.tool_calls.present?
      msg_hash
    end
  end

  private

  # Some LLM providers may not accept image-only messages.
  # Ensure that if there are images but no text or audio, we add some text.
  def ensure_text_present
    if content.blank? && audios.empty? && images.any?
      Rails.logger.info "Images with empty message content. Adding some text."
      self.content = "See image(s)."
    end
  end

  def check_context_limit
    return unless role_user? # Only run this check for user messages
    Rails.logger.debug "Checking context limit for message: #{self.inspect}"

    # Get the model's context limit
    llm = conversation.llm_in_use
    return unless llm
    context_limit = llm.context_length
    return unless context_limit # Skip if context limit is not set

    # Check the threshold (model's context limit - 64,000)
    threshold = context_limit - 64000

    if conversation.last_prompt_tokens > threshold
      Rails.logger.warn("Conversation #{conversation.id} is approaching the context limit: #{conversation.last_prompt_tokens} / #{threshold}")
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
