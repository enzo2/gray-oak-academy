class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  enum :role, { system: "system", assistant: "assistant", user: "user" }, prefix: true
  # ? acts_as_list scope: :conversation  #MEssages are ordered correctly without this.
  belongs_to :conversation

  # Message content field contains text.
  # Images are kept separately.
  has_many :images, dependent: :destroy

  after_create_commit -> { broadcast_created }
  after_update_commit -> { broadcast_updated }

  def broadcast_created
    broadcast_append_later_to(
      "#{dom_id(conversation)}",
      partial: "messages/message",
      locals: { message: self, scroll_to: true },
      target: "#{dom_id(conversation)}_messages"
    )
  end

  def broadcast_updated
    broadcast_append_to(
      "#{dom_id(conversation)}",
      partial: "messages/message",
      locals: { message: self, scroll_to: true },
      target: "#{dom_id(conversation)}_messages"
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
end
