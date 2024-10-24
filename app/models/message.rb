class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  enum :role, { system: "system", assistant: "assistant", user: "user" }, prefix: true
  # ? acts_as_list scope: :conversation
  belongs_to :conversation

  after_create_commit -> { broadcast_created }
  after_update_commit -> { broadcast_updated }

  def broadcast_created
    broadcast_append_later_to(
      "#{dom_id(conversation)}_messages",
      partial: "messages/message",
      locals: { message: self, scroll_to: true },
      target: "#{dom_id(conversation)}_messages"
    )
  end

  def broadcast_updated
    broadcast_append_to(
      "#{dom_id(conversation)}_messages",
      partial: "messages/message",
      locals: { message: self, scroll_to: true },
      target: "#{dom_id(conversation)}_messages"
    )
  end

  # Format the messages for the LLM api
  def self.for_completion(messages)
    messages.map { |message| { role: message.role, content: message.content } }
  end
end
