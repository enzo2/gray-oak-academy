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

    function_call_adapter = ResponsesFunctionCallAdapter.new(
      current_user: user,
      conversation: conversation,
      exa_enabled: AppSetting.exa_enabled?
    )

    client = OpenaiResponsesService.new(
      current_user: user,
      conversation: conversation,
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
    history_messages = stateful_supported ? nil : deep_dup_messages(messages)

    response_hash = complete_and_capture_response(client, messages: messages)
    final_message_id = nil
    turns = 0

    loop do
      persisted = persist_assistant_message(
        conversation: conversation,
        response_hash: response_hash,
        client: client,
        function_call_adapter: function_call_adapter
      )
      assistant_message = persisted[:message]
      history_messages << persisted[:payload] if history_messages && persisted[:payload].present?
      final_message_id = assistant_message&.id if assistant_message

      function_calls = function_call_adapter.function_calls(response_hash)
      break if function_calls.blank?

      turns += 1
      if turns > MAX_TOOL_TURNS
        raise OpenAiError, "Tool-call limit exceeded (#{MAX_TOOL_TURNS}). Ask the user to confirm how to proceed."
      end

      tool_outputs = function_call_adapter.function_call_outputs(function_calls)

      if stateful_supported
        response_hash = complete_and_capture_response(
          client,
          input: tool_outputs,
          previous_response_id: response_hash["id"]
        )
      else
        history_messages.concat(function_call_outputs_to_tool_messages(tool_outputs))
        response_hash = complete_and_capture_response(client, messages: history_messages)
      end
    end

    if final_message_id.present?
      broadcast_completion_finished(conversation, final_message_id)
    else
      broadcast_warning("LLM returned an empty response.", conversation)
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

  def complete_and_capture_response(client, messages: nil, input: nil, previous_response_id: nil)
    client.complete(messages, input: input, previous_response_id: previous_response_id)
    response_hash = client.last_response_hash
    raise OpenAiError, "Responses API did not return a valid response payload." if response_hash.blank?

    response_hash
  end

  def persist_assistant_message(conversation:, response_hash:, client:, function_call_adapter:)
    text = client.output_text(response_hash)
    function_calls = function_call_adapter.function_calls(response_hash)
    tool_calls = function_call_adapter.function_calls_as_chat_tool_calls(function_calls)

    content_blank = effectively_blank_text?(text)
    return { message: nil, payload: nil } if content_blank && tool_calls.blank?

    payload = {
      role: "assistant",
      content: content_blank ? nil : text,
      tool_calls: tool_calls.presence
    }.compact

    message = Message.create!(
      conversation: conversation,
      role: "assistant",
      content: content_blank ? nil : text,
      tool_calls: tool_calls.presence
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
