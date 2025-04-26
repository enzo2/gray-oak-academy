class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  self.implicit_order_column = "created_at" # just in case IDs get out of order somehow

  enum :role, { system: "system", assistant: "assistant", user: "user" }, prefix: true

  belongs_to :conversation
  has_many :images, dependent: :destroy # Message content field contains text. Images are kept separately.
  has_many :audios, dependent: :destroy # Audio is kept separately.

  before_create :ensure_text_present

  # Include broadcast logic in the model, since it's an inherent property of Messages that they will need to be viewed immediately.
  after_create_commit -> { broadcast_created; check_context_limit }
  after_update_commit -> { broadcast_updated }
  after_destroy_commit -> { broadcast_destroyed }

  def broadcast_created
    Rails.logger.debug "Broadcasting created message: #{self.inspect}"
    # Docs recommend broadcast_append_later_to, but this causes view to render first, putting the assistant message placeholder out of order.
    # using broadcast_append_to forces the new user message to be broadcast before we move onto the assistant message.
    # Does not appear to cause any significant slowdown.
    broadcast_append_to(
      "#{dom_id(conversation)}",
      partial: "messages/message",
      locals: { message: self },
      target: "#{dom_id(conversation)}"
    )
    # Remove any temporary new message placeholder
    broadcast_remove_to("#{dom_id(conversation)}", target: "new_message") if role_assistant?
  end

  def broadcast_updated
    Rails.logger.debug "Broadcasting updated message: #{self.inspect}"
    # Due to https://github.com/hotwired/turbo-rails/issues/644, we need extract the inner_html of the message partial.
    # This allows same partial to be used for create and update.
    html = ApplicationController.renderer_with_signed_in_user(conversation.user).render(partial: "messages/message", locals: { message: self })
    dom = Nokogiri::HTML.fragment(html)
    html = dom.at_css(":root").inner_html
    broadcast_update_later_to(
      "#{dom_id(conversation)}",
      target: dom_id(self),
      html: html
    )
  end

  def broadcast_destroyed
    Rails.logger.debug "Broadcasting destroyed message: #{self.inspect}"
    broadcast_remove_to("#{dom_id(conversation)}", target: dom_id(self))
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

  # Return content in JSON format with base64 images and audio for LLM APIs.
  def content_with_media
    base_content = content_with_images
    return base_content if audios.empty?

    # If base_content is just a string (text only or empty), convert to array format
    content_json = base_content.is_a?(String) ? [ { "type": "text", "text": base_content } ] : base_content

    audios.each do |audio|
      audio_data = audio.base64_for_LLM
      content_json << { "type": "input_audio", "input_audio": audio_data } if audio_data
    end
    content_json
  end

  # Format messages for the LLM api
  def self.for_completion_with_media(messages:, audio: false)
    # Some LLM providers don't like blank messages.
    # Right now, none should be blank since we add "See image(s)" if there are images and no text.
    # if messages.last.content.empty?
    #  messages = messages[0...-1]
    # end
    if audio
      messages.map { |message| { role: message.role, content: message.content_with_media } }
    else
      messages.map { |message| { role: message.role, content: message.content_with_images } }
    end
  end

  private

  # Some LLM providers do not accept empty messages even if an image is present.
  # This callback ensures that if there are images but no text, we add some text.
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
