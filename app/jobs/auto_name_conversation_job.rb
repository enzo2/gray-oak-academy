# Auto-name a conversation based on its early messages, and broadcast the updated title to the chat view.
class AutoNameConversationJob < ApplicationJob
  include ActionView::RecordIdentifier

  queue_as :default
  limits_concurrency to: 1, key: ->(conversation:) { "auto_name_conversation_#{conversation.id}" }

  TITLE_SCHEMA = {
    strict: true,
    name: "Conversation_Title",
    description: "A concise, specific title for a conversation. May be blank string if not enough information is available.",
    schema: LlmSchemas::ConversationTitleSchema.to_json_schema.deep_stringify_keys
  }.freeze

  def perform(conversation:)
    conversation.reload
    return unless conversation.auto_name_candidate?

    user = conversation.user
    excerpt = build_excerpt(conversation)
    return if excerpt.blank?

    customized_prompt = Prompt.get_prompt(category: "auto_name_conversation", user: user)
      .gsub("{conversation_excerpt}", excerpt)

    client = OpenaiApiService.new(current_user: user, conversation: conversation)
    parsed = client.complete(
      [ { role: "user", content: customized_prompt } ],
      response_format: {
        type: "json_schema",
        json_schema: TITLE_SCHEMA.slice(:name, :schema, :strict)
      },
      schema: TITLE_SCHEMA[:schema],
      prefill: "{\"title\":\""
    )

    title = sanitize_title(parsed["title"])
    return if title.blank?

    updated = false
    conversation.with_lock do
      conversation.reload
      next unless conversation.auto_name_candidate?

      conversation.update!(title: title)
      updated = true
    end

    broadcast_title_update(conversation) if updated
  rescue StandardError => e
    Rails.logger.error "AutoNameConversationJob Error for conversation #{conversation&.id}: #{e.message}"
  end

  private

  def build_excerpt(conversation)
    messages = conversation.messages
      .where(role: %w[user assistant])
      .order(created_at: :asc)
      .limit(12)

    lines = []
    total_chars = 0

    messages.each do |message|
      text = message.content.to_s.strip
      next if text.blank?

      text = text.gsub(/\s+/, " ")[0, 500]
      label = message.role_user? ? "User" : "Assistant"
      line = "#{label}: #{text}"

      total_chars += line.length
      break if total_chars > 3000

      lines << line
    end

    lines.join("\n")
  end

  def sanitize_title(raw)
    title = raw.to_s.strip
    title = title.delete_prefix("\"").delete_suffix("\"")
    title = title.gsub(/\s+/, " ").strip
    title = title.delete_suffix(".").delete_suffix(":").delete_suffix("-")
    title[0, 80]
  end

  def broadcast_title_update(conversation)
    Turbo::StreamsChannel.broadcast_replace_to(
      dom_id(conversation),
      target: dom_id(conversation, :sidebar_link),
      partial: "conversations/sidebar_link",
      locals: { conversation: conversation, current_conversation: conversation }
    )
  end

  def broadcast_error(conversation, message)
    Turbo::StreamsChannel.broadcast_update_to(
      "#{dom_id(conversation)}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { warning: message } }
    )
  end
end
