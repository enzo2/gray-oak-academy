# Job submits a conversation to the Responses API wrapper service, handles tool calls,
# and broadcasts completion events to the user.
class GetResponsesCompletionJob < ApplicationJob
  require "securerandom"

  include ActionView::RecordIdentifier
  include ApplicationHelper
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation:) { conversation }, duration: 1.minutes

  MAX_TOOL_TURNS = 20

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

    stateful_supported = !client.respond_to?(:stateful_supported?) || client.stateful_supported?
    chained_state = stateful_supported && client.respond_to?(:previous_response_id) && client.previous_response_id.present?
    reasoning_options = reasoning_options_for(stateful_supported: stateful_supported)

    message_records = chained_state ? trailing_user_message_records(conversation.messages) : conversation.messages
    if chained_state && message_records.blank?
      raise OpenAiError, "No new user messages available for chained Responses request."
    end
    initial_messages = Message.for_completion(
      messages: message_records,
      audio: conversation.audio_input_permitted?,
      images: include_images
    )

    start_stream_turn!(state: stream_state)
    response_hash = complete_and_capture_response(
      client,
      messages: initial_messages,
      reasoning: reasoning_options,
      stream_state: stream_state
    )
    flush_stream_content!(conversation: conversation, state: stream_state, force: true)
    native_transcript = nil
    unless stateful_supported
      native_transcript = ResponsesNativeTranscript.new(initial_input_items: client.last_input_items)
      unless native_transcript.reasoning_replayable_for_tool_boundary?(response_hash)
        Rails.logger.warn(
          "Stateless Responses chat reasoning fallback used conversation=#{conversation.id} user=#{user.id} " \
          "provider=#{client.respond_to?(:base_uri) ? client.base_uri : 'unknown'} " \
          "model=#{client.respond_to?(:model) ? client.model : 'unknown'} response_id=#{response_hash['id']}"
        )
        discard_streamed_assistant_message!(conversation: conversation, state: stream_state)
        reasoning_options = { effort: "none" }
        start_stream_turn!(state: stream_state)
        response_hash = complete_and_capture_response(
          client,
          messages: initial_messages,
          reasoning: reasoning_options,
          stream_state: stream_state
        )
        flush_stream_content!(conversation: conversation, state: stream_state, force: true)
        native_transcript = ResponsesNativeTranscript.new(initial_input_items: client.last_input_items)
      end
      append_stateless_response!(
        transcript: native_transcript,
        response_hash: response_hash,
        reasoning_options: reasoning_options
      )
    end
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
          reasoning: reasoning_options,
          stream_state: stream_state
        )
        flush_stream_content!(conversation: conversation, state: stream_state, force: true)
      else
        native_transcript.append_function_call_outputs!(tool_outputs)
        start_stream_turn!(state: stream_state)
        response_hash = complete_and_capture_response(
          client,
          input: native_transcript.input_items,
          reasoning: reasoning_options,
          stream_state: stream_state
        )
        flush_stream_content!(conversation: conversation, state: stream_state, force: true)
        unless reasoning_options[:effort] == "none" || native_transcript.reasoning_replayable_for_tool_boundary?(response_hash)
          raise OpenAiError,
                "Stateless Responses reasoning became unreplayable after tools had executed; refusing an unsafe restart."
        end
        append_stateless_response!(
          transcript: native_transcript,
          response_hash: response_hash,
          reasoning_options: reasoning_options
        )
      end
    end

    if final_message_id.present?
      broadcast_completion_finished(conversation, final_message_id)
    else
      broadcast_warning("LLM returned an empty response.", conversation)
      Turbo::StreamsChannel.broadcast_remove_to("#{dom_id(conversation)}", target: "new_message")
      broadcast_completion_finished(conversation, nil)
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

  def append_stateless_response!(transcript:, response_hash:, reasoning_options:)
    omit_reasoning = reasoning_options[:effort] == "none" &&
      !transcript.reasoning_replayable_for_tool_boundary?(response_hash)
    if omit_reasoning
      Rails.logger.warn(
        "Provider returned unreplayable reasoning after reasoning was disabled; omitting reasoning items from stateless chat replay."
      )
    end
    transcript.append_response!(response_hash, omit_reasoning: omit_reasoning)
  end

  def complete_and_capture_response(client, messages: nil, input: nil, previous_response_id: nil, reasoning: nil, stream_state: nil)
    client.complete(
      messages,
      input: input,
      previous_response_id: previous_response_id,
      reasoning: reasoning
    )
    response_hash = client.last_response_hash.presence || synthesize_stream_response_hash(stream_state)
    raise OpenAiError, "Responses API did not return a valid response payload." if response_hash.blank?
    raise_on_response_refusal!(response_hash)

    response_hash
  end

  def reasoning_options_for(stateful_supported:)
    options = { effort: "low" }
    options[:summary] = "auto" if stateful_supported
    options
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

  # Persist reasoning items only for assistant turns that include tool calls.
  # This mirrors Chat Completions policy and avoids storing hidden chain-of-thought
  # on ordinary conversational replies.
  def extract_tool_call_reasoning_details(response_hash, tool_calls)
    return nil if tool_calls.blank?

    details = Array(response_hash["output"]).filter_map do |item|
      next unless item["type"].to_s == "reasoning"
      next unless ResponsesNativeTranscript::OPAQUE_REASONING_KEYS.any? { |key| item[key].present? }

      item.deep_dup
    end

    details.presence
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
  # Slice records before serializing media so old images are not base64-encoded locally.
  def trailing_user_message_records(messages)
    Array(messages).reverse.take_while { |message| message.role.to_s == "user" }.reverse
  end

  def build_stream_state
    {
      message: nil,
      content_buffer: +"",
      last_update_time: Time.current,
      update_interval: 0.120
    }
  end

  def synthesize_stream_response_hash(stream_state)
    return nil unless stream_state.is_a?(Hash)

    buffered_text = +""
    buffered_text << stream_state[:message].content.to_s if stream_state[:message].present?
    buffered_text << stream_state[:content_buffer].to_s
    return nil if buffered_text.blank?

    {
      "id" => "resp_stream_job_fallback_#{SecureRandom.hex(8)}",
      "status" => "completed",
      "output" => [
        {
          "type" => "message",
          "content" => [
            { "type" => "output_text", "text" => buffered_text }
          ]
        }
      ],
      "usage" => {}
    }
  end

  def start_stream_turn!(state:)
    state[:message] = nil
    state[:content_buffer] = +""
    state[:last_update_time] = Time.current
  end

  def discard_streamed_assistant_message!(conversation:, state:)
    message = state[:message]
    return unless message&.persisted?

    target = dom_id(message)
    message.destroy!
    Turbo::StreamsChannel.broadcast_remove_to(dom_id(conversation), target: target)
  ensure
    start_stream_turn!(state: state)
  end

  def responses_stream_handler(conversation:, state:)
    Proc.new do |event|
      begin
        event_type = event["type"].to_s
        case event_type
        when "response.output_text.delta"
          delta = event["delta"].to_s
          next if delta.empty?

          state[:content_buffer] << delta
          flush_stream_content!(conversation: conversation, state: state)
        when "response.output_text.done"
          append_stream_completion_text!(state: state, text: event["text"])
          flush_stream_content!(conversation: conversation, state: state, force: true)
        when "response.content_part.done"
          part = event["part"]
          if part.is_a?(Hash) && part["type"].to_s == "output_text"
            append_stream_completion_text!(state: state, text: part["text"])
          end
          flush_stream_content!(conversation: conversation, state: state, force: true)
        when "response.output_item.done"
          append_stream_completion_text!(state: state, text: extract_output_item_text(event["item"]))
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
    return if state[:content_buffer].empty?

    update_due = force || state[:message].nil? || (Time.current - state[:last_update_time] > state[:update_interval])
    return unless update_due

    state[:message] ||= conversation.messages.build(role: "assistant")
    current_content = state[:message].persisted? ? state[:message].content.to_s : ""
    state[:message].content = current_content + state[:content_buffer]
    state[:message].save!
    state[:content_buffer] = +""
    state[:last_update_time] = Time.current
  end

  def append_stream_completion_text!(state:, text:)
    completion_text = text.to_s
    return if completion_text.empty?
    message_content = state[:message]&.content.to_s
    return unless state[:content_buffer].empty? && message_content.empty?

    state[:content_buffer] << completion_text
  end

  def extract_output_item_text(item)
    return "" unless item.is_a?(Hash)
    return "" unless item["type"].to_s == "message"

    Array(item["content"]).filter_map do |part|
      next unless part.is_a?(Hash)
      next unless part["type"].to_s == "output_text"

      part["text"].to_s.presence
    end.join
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
    broadcast_dispatch_event(
      conversation: conversation,
      event_name: "llm-completion-error",
      payload: { conversation_id: conversation.id }
    )
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
    Rails.logger.debug("Broadcasting completion finished event to conversation: #{conversation.id}")
    broadcast_dispatch_event(
      conversation: conversation,
      event_name: "llm-completion-finished",
      payload: {
        message_id: message_id,
        conversation_id: conversation.id,
        tool_call_pending: false
      }
    )
  end

  def broadcast_dispatch_event(conversation:, event_name:, payload:)
    Turbo::StreamsChannel.broadcast_action_to(
      "#{dom_id(conversation)}",
      action: :dispatch_event,
      attributes: {
        "event-name": event_name,
        "target-selector": "##{dom_id(conversation)}"
      },
      content: payload.to_json
    )
  end
end
