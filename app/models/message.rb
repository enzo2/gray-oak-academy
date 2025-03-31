class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  self.implicit_order_column = "created_at" # just in case IDs get out of order somehow

  enum :role, { system: "system", assistant: "assistant", user: "user" }, prefix: true

  belongs_to :conversation
  has_many :images, dependent: :destroy # Message content field contains text. Images are kept separately.

  before_create :ensure_text_present

  # Include broadcast logic in the model, since it's an inherent property of Messages that they will need to be viewed immediately.
  after_create_commit -> { broadcast_created; check_context_limit }
  after_update_commit -> { broadcast_updated }

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
    broadcast_remove_to("#{dom_id(conversation)}", target: "new_message")
  end

  def broadcast_updated
    Rails.logger.debug "Broadcasting updated message: #{self.inspect}"
    html = ApplicationController.render(partial: "messages/message", locals: { message: self })
    dom = Nokogiri::HTML.fragment(html)
    html = dom.at_css(":root").inner_html # Remove the root element, since we don't want to replace the whole message. Allows same partial to be used for create and update.
    broadcast_update_later_to(
      "#{dom_id(conversation)}",
      target: dom_id(self),
      html: html
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

  # Format messages for the LLM api
  def self.for_completion_with_images(messages)
    # Some LLM providers don't like blank messages.
    # Right now, none should be blank since we add "See image(s)" if there are images and no text.
    # if messages.last.content.empty?
    #  messages = messages[0...-1]
    # end
    messages.map { |message| { role: message.role, content: message.content_with_images } }
  end

  private

  # Some LLM providers do not accept empty messages even if an image is present.
  # This callback ensures that if there are images but no text, we add some text.
  def ensure_text_present
    if content.blank? && images.any?
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
