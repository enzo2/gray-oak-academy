# Job submits a conversation to the Responses API wrapper service, handles tool calls,
# and broadcasts completion events to the user.
class GetResponsesCompletionJob < ApplicationJob
  include ActionView::RecordIdentifier
  include ApplicationHelper
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation:) { conversation }, duration: 1.minutes

  MAX_TOOL_TURNS = 10

  def perform(conversation:)
    user = conversation.user
    include_images = conversation.image_input_supported?
    stream_state = build_stream_state

    function_call_adapter = ResponsesFunctionCallAdapter.new(
      current_user: user,
      conversation: conversation,
      exa_enabled: AppSetting.exa_enabled?
    )

    client = OpenaiResponsesService.new(
      current_user: user,
      conversation: conversation,
      stream_handler: responses_stream_handler(conversation: conversation, state: stream_state),
      task_system_prompt: conversation.task_system_prompt,
      enable_tools: true,
      flow_tools: function_call_adapter.conversation_flow_tools
    )

    messages = Message.for_completion(
      messages: conversation.messages,
      audio: conversation.audio_input_permitted?,
      images: include_images
    )

    stateful_supported = !client.respond_to?(:stateful_supported?) || client.stateful_supported?
    chained_state = stateful_supported && client.respond_to?(:previous_response_id) && client.previous_response_id.present?
    history_messages = stateful_supported ? nil : deep_dup_messages(messages)

    initial_messages = chained_state ? trailing_user_messages(messages) : messages
    if chained_state && initial_messages.blank?
      raise OpenAiError, "No new user messages available for chained Responses request."
    end

    start_stream_turn!(state: stream_state)
    response_hash = complete_and_capture_response(
      client,
      messages: initial_messages,
      reasoning: reasoning_options_for(stateful_supported: stateful_supported)
    )
    flush_stream_content!(conversation: conversation, state: stream_state, force: true)
    final_message_id = nil
    turns = 0

    loop do
      persisted = persist_assistant_message(
        conversation: conversation,
        response_hash: response_hash,
        client: client,
        function_call_adapter: function_call_adapter,
        stream_message: stream_state[:message]
      )
      assistant_message = persisted[:message]
      history_messages << persisted[:payload] if history_messages && persisted[:payload].present?

      function_calls = function_call_adapter.function_calls(response_hash)
      if function_calls.blank?
        final_message_id = assistant_message&.id
        break
      end

      turns += 1
      if turns > MAX_TOOL_TURNS
        raise OpenAiError, "Tool-call limit exceeded (#{MAX_TOOL_TURNS}). Ask the user to confirm how to proceed."
      end

      tool_outputs = function_call_adapter.function_call_outputs(function_calls)

      if stateful_supported
        start_stream_turn!(state: stream_state)
        response_hash = complete_and_capture_response(
          client,
          input: tool_outputs,
          previous_response_id: response_hash["id"],
          reasoning: reasoning_options_for(stateful_supported: stateful_supported)
        )
        flush_stream_content!(conversation: conversation, state: stream_state, force: true)
      else
        history_messages.concat(function_call_outputs_to_tool_messages(tool_outputs))
        start_stream_turn!(state: stream_state)
        response_hash = complete_and_capture_response(client, messages: history_messages)
        flush_stream_content!(conversation: conversation, state: stream_state, force: true)
      end
    end

    if final_message_id.present?
      broadcast_completion_finished(conversation, final_message_id)
    else
      broadcast_warning("LLM returned an empty response.", conversation)
      Turbo::StreamsChannel.broadcast_remove_to("#{dom_id(conversation)}", target: "new_message")
    end

    if include_images == false && conversation.messages.role_user.count == 1
      broadcast_warning("This model does not support image input. It's highly recommended to use a multimodal model.", conversation)
    end

    # After done, see if we need to transcribe any audio messages.
    conversation.messages.role_user.joins(:audios).distinct.each do |msg|
      Rails.logger.info "Enqueueing transcription jobs for audio attachments on Message ID #{msg.id}."
      TranscribeAudioJob.perform_later(audio: msg.audios.first)
    end

  rescue OpenAiError => e
    Rails.logger.error "OpenAiService: #{e.message}"
    # Destroy the last message if it was a user message, since it was not sent and may have caused an error
    destroy_last_user_message_if_latest!(conversation)
    broadcast_error(e.message.to_s, conversation)
    raise
  rescue StandardError => e
    Rails.logger.error "Error in GetResponsesCompletionJob: #{e.message}"
    broadcast_error("Failed to get LLM completion: #{e.message}", conversation)
    raise
  end

  private

  def complete_and_capture_response(client, messages: nil, input: nil, previous_response_id: nil, reasoning: nil)
    client.complete(messages, input: input, previous_response_id: previous_response_id, reasoning: reasoning)
    response_hash = client.last_response_hash
    raise OpenAiError, "Responses API did not return a valid response payload." if response_hash.blank?
    raise_on_response_refusal!(response_hash)

    response_hash
  end

  def reasoning_options_for(stateful_supported:)
    return nil unless stateful_supported

    { summary: "auto" }
  end

  def persist_assistant_message(conversation:, response_hash:, client:, function_call_adapter:, stream_message: nil)
    text = client.output_text(response_hash)
    function_calls = function_call_adapter.function_calls(response_hash)
    tool_calls = function_call_adapter.function_calls_as_chat_tool_calls(function_calls)
    reasoning_details = extract_tool_call_reasoning_details(response_hash, tool_calls)

    content_blank = effectively_blank_text?(text)
    if stream_message.present?
      message = stream_message
      if !content_blank && effectively_blank_text?(message.content)
        message.update!(content: text)
      end
      if tool_calls.present? && message.tool_calls != tool_calls
        message.update!(tool_calls: tool_calls)
      end
      if message.reasoning_details != reasoning_details
        message.update!(reasoning_details: reasoning_details)
      end

      final_content_blank = effectively_blank_text?(message.content)
      final_tool_calls_blank = message.tool_calls.blank?
      return { message: nil, payload: nil } if final_content_blank && final_tool_calls_blank

      payload = {
        role: "assistant",
        content: final_content_blank ? nil : message.content,
        tool_calls: message.tool_calls.presence,
        reasoning_details: message.reasoning_details.presence
      }.compact

      return { message: message, payload: payload }
    end

    return { message: nil, payload: nil } if content_blank && tool_calls.blank?

    payload = {
      role: "assistant",
      content: content_blank ? nil : text,
      tool_calls: tool_calls.presence,
      reasoning_details: reasoning_details.presence
    }.compact

    message = Message.create!(
      conversation: conversation,
      role: "assistant",
      content: content_blank ? nil : text,
      tool_calls: tool_calls.presence,
      reasoning_details: reasoning_details.presence
    )

    { message: message, payload: payload }
  end

  def function_call_outputs_to_tool_messages(function_call_outputs)
    Array(function_call_outputs).filter_map do |function_call_output|
      call_id = function_call_output[:call_id] || function_call_output["call_id"]
      next if call_id.blank?

      {
        role: "tool",
        tool_call_id: call_id,
        content: function_call_output[:output] || function_call_output["output"] || ""
      }
    end
  end

  def deep_dup_messages(messages)
    Array(messages).map { |message| message.is_a?(Hash) ? message.deep_dup : message }
  end

  # Persist reasoning items only for assistant turns that include tool calls.
  # This mirrors Chat Completions policy and avoids storing hidden chain-of-thought
  # on ordinary conversational replies.
  def extract_tool_call_reasoning_details(response_hash, tool_calls)
    return nil if tool_calls.blank?

    details = Array(response_hash["output"]).filter_map do |item|
      next unless item["type"].to_s == "reasoning"

      normalize_reasoning_detail(item)
    end

    details.presence
  end

  def normalize_reasoning_detail(item)
    encrypted_content = item["encrypted_content"].to_s
    summary = normalize_reasoning_summary(item["summary"])
    id = item["id"].to_s
    status = item["status"].to_s

    detail = {
      "type" => "reasoning",
      "id" => id.presence,
      "status" => status.presence,
      "summary" => summary.presence,
      "encrypted_content" => encrypted_content.presence
    }.compact

    detail.except("type").present? ? detail : nil
  end

  def normalize_reasoning_summary(summary)
    case summary
    when String
      text = summary.strip
      return [] if text.blank?

      [ { "type" => "summary_text", "text" => text } ]
    when Array
      summary.filter_map { |entry| normalize_reasoning_summary_entry(entry) }
    when Hash
      entry = normalize_reasoning_summary_entry(summary)
      entry.present? ? [ entry ] : []
    else
      []
    end
  end

  def normalize_reasoning_summary_entry(entry)
    return nil unless entry.is_a?(Hash)

    type = entry["type"].to_s.presence || "summary_text"
    text = entry["text"].to_s
    text = entry["summary_text"].to_s if text.blank?
    text = text.strip
    return nil if text.blank?

    { "type" => type, "text" => text }
  end

  def raise_on_response_refusal!(response_hash)
    refusal = response_refusal_message(response_hash)
    return if refusal.blank?

    raise OpenAiError, "Response refused with message: #{refusal}"
  end

  def response_refusal_message(response_hash)
    Array(response_hash["output"]).each do |item|
      next unless item["type"].to_s == "message"

      Array(item["content"]).each do |content|
        next unless content["type"].to_s == "refusal"

        refusal = content["refusal"] || content["text"]
        refusal_text = refusal.to_s.strip
        return refusal_text if refusal_text.present?
        return "The model refused to answer."
      end
    end

    nil
  end

  # In stateful mode with previous_response_id, send only new user turns.
  # This avoids duplicate item IDs when replaying assistant/tool history.
  def trailing_user_messages(messages)
    Array(messages).reverse.take_while { |message| (message[:role] || message["role"]).to_s == "user" }.reverse
  end

  def build_stream_state
    {
      message: nil,
      content_buffer: +"",
      last_update_time: Time.current,
      update_interval: 0.120
    }
  end

  def start_stream_turn!(state:)
    state[:message] = nil
    state[:content_buffer] = +""
    state[:last_update_time] = Time.current
  end

  def responses_stream_handler(conversation:, state:)
    Proc.new do |event|
      begin
        event_type = event["type"].to_s
        case event_type
        when "response.output_text.delta"
          delta = event["delta"].to_s
          next if delta.blank?

          state[:content_buffer] << delta
          flush_stream_content!(conversation: conversation, state: state)
        when "response.output_text.done"
          text = event["text"].to_s
          if text.present? && state[:message].nil? && state[:content_buffer].blank?
            state[:content_buffer] << text
          end
          flush_stream_content!(conversation: conversation, state: state, force: true)
        when "response.completed"
          flush_stream_content!(conversation: conversation, state: state, force: true)
        else
          # Ignore non-text events here. Tool calls are finalized from last_response_hash.
        end
      rescue StandardError => e
        Rails.logger.error "Error during Responses streaming event handling: #{e.message}"
        raise
      end
    end
  end

  def flush_stream_content!(conversation:, state:, force: false)
    return if state[:content_buffer].blank?

    update_due = force || state[:message].nil? || (Time.current - state[:last_update_time] > state[:update_interval])
    return unless update_due

    state[:message] ||= conversation.messages.build(role: "assistant")
    current_content = state[:message].persisted? ? state[:message].content.to_s : ""
    state[:message].content = current_content + state[:content_buffer]
    state[:message].save!
    state[:content_buffer] = +""
    state[:last_update_time] = Time.current
  end

  def destroy_last_user_message_if_latest!(conversation)
    latest_role = conversation.messages.reorder(created_at: :desc).limit(1).pick(:role)
    return unless latest_role == "user"

    conversation.messages.role_user.reorder(created_at: :desc).first&.destroy
  end

  def broadcast_error(message, conversation)
    Rails.logger.debug("Broadcasting error to conversation: #{conversation.id}")
    Turbo::StreamsChannel.broadcast_update_to(
      "#{dom_id(conversation)}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
    Turbo::StreamsChannel.broadcast_remove_to("#{dom_id(conversation)}", target: "new_message")
  end

  def broadcast_warning(message, conversation)
    Turbo::StreamsChannel.broadcast_update_to(
      "#{dom_id(conversation)}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { warning: message } }
    )
  end

  def broadcast_completion_finished(conversation, message_id)
    return if message_id.blank?

    Rails.logger.debug("Broadcasting completion finished event to conversation: #{conversation.id}")
    Turbo::StreamsChannel.broadcast_action_to(
      "#{dom_id(conversation)}",
      action: :dispatch_event,
      attributes: {
        "event-name": "llm-completion-finished",
        "target-selector": "##{dom_id(conversation)}"
      },
      content: { message_id: message_id }.to_json
    )
  end
end
