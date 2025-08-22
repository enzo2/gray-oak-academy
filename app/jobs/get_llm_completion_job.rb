# Job submits a conversation to the LLM API wrapper service, handles the streamed response, and broadcasts the response to the user.
class GetLlmCompletionJob < ApplicationJob
  include ActionView::RecordIdentifier
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation:) { conversation }, duration: 1.minutes

  # Add a task_system_prompt to the conversation, and it will be appended to the base system prompts.
  # Otherwise, the default system prompt will be used without any further instructions.

  def perform(conversation:)
    user = conversation.user

    client = OpenaiApiService.new( # Uses ruby-openai gem (not just for OpenAI, supports any OpenAI-compatible API):
      current_user: user,
      stream_handler: stream_handler(conversation: conversation),
      task_system_prompt: conversation.task_system_prompt,
      enable_tools: true,
      conversation: conversation
    )

    # Get the array of message hashes with roles and content
    messages = Message.for_completion_with_media(messages: conversation.messages, audio: conversation.audio_input_permitted?)

    client.complete(messages)     # Should return an empty string once completed, since we used streaming.

    # After done, see if we need to transcribe any audio messages.
    conversation.messages.role_user.joins(:audios).distinct.each do |msg|
      Rails.logger.info "Enqueueing transcription jobs for audio attachments on Message ID #{msg.id}."
      TranscribeAudioJob.perform_later(audio: msg.audios.first)
    end

  rescue OpenAiError => e
    Rails.logger.error "OpenAiService: #{e.message}"
    # Destroy the last message if it was a user message, since it was not sent and may have caused an error
    conversation.messages.role_user.last&.destroy if conversation.messages.last&.role_user?
    broadcast_error("#{e.message}", conversation)
    raise
  rescue StandardError => e
    Rails.logger.error "Error in GetLLMCompletionJob: #{e.message}"
    broadcast_error("Failed to get LLM completion: #{e.message} \n", conversation)
    raise e # This will trigger a retry
  end

  private

  def stream_handler(conversation:)
    # Initialize the message variable. Don't save to DB yet since the request might fail.
    message = nil

    # Buffer for accumulating tool calls by index
    tool_calls_buffer = {}
    # Buffer for message content to slow down unnecessarily rapid streams
    content_buffer = ""
    last_update_time = Time.current
    update_interval = 0.120 # seconds. Want to balance a fast UX with reducing turbo_stream broadcasts

    # Method to flush the message content buffer
    flush_buffer = ->(force: false) do
      return if content_buffer.empty?
      if force || message.nil? || (Time.current - last_update_time > update_interval)
        message ||= conversation.messages.build(role: "assistant")
        message.content = (message.persisted? ? message.content : "") + content_buffer
        message.save! # This will broadcast the new or updated message via callbacks in the model
        content_buffer = "" # Clear the buffer after flushing
        last_update_time = Time.current
        Rails.logger.debug "Flushed message content buffer to DB"
      end
    end

    # Return a proc that handles the streamed response
    Proc.new do |chunk|
      begin
        # Check if the chunk contains tool calls, and accumulate them by index
        if chunk.dig("delta", "tool_calls").present?
          Rails.logger.debug "Tool call chunk: #{chunk.inspect}"
          chunk.dig("delta", "tool_calls").each do |tool_call|
            idx = tool_call["index"] || 0
            # Initialize the tool call entry in the buffer if this is the first chunk for this tool call
            tool_calls_buffer[idx] ||= {
              type: tool_call["type"] || "function",
              # Gemini OpenAI Compatibility API bug workaround - it gives an empty string as ID, but needs one later or gives a 400 error
              id: tool_call["id"].blank? ? "call_#{SecureRandom.alphanumeric(24)}" : tool_call["id"],
              function: {
                name: tool_call.dig("function", "name"),
                arguments: "" # Initialize as empty string, will be updated with actual arguments
              }
            }
            # id/type/name are supposed to be set in the first chunk, so we won't change them.
            # Append arguments
            tool_calls_buffer[idx][:function][:arguments] += tool_call.dig("function", "arguments") if tool_call.dig("function", "arguments")
          end
        end

        # Finalize and execute tool calls when finish reason indicates tool call completion
        if chunk["finish_reason"] == "tool_calls"
          flush_buffer.call(force: true) # Ensure any remaining content is flushed before handling tools
          broadcast_completion_finished(conversation, message.id) # Broadcast completion now, since tool may take a while
          final_tool_calls = tool_calls_buffer.values.sort_by { |tc| tc[:id].to_s }
          message.update!(tool_calls: final_tool_calls) # Add tool calls to the message
          Rails.logger.debug "Tool call streamed. Calling tool(s): #{final_tool_calls.inspect}"
          final_tool_calls.each do |tool_call|
            tool_handler = ToolHandlerService.new(conversation: conversation, message: message)
            tool_handler.execute_tool_call({
              name: tool_call[:function][:name],
              arguments: tool_call[:function][:arguments],
              id: tool_call[:id]
            })
          end
          tool_calls_buffer.clear # Clear buffer for subsequent tool calls
        elsif chunk.dig("delta", "content")&.length&. > 0
          # For standard content, append the new chunk to the buffer
          Rails.logger.debug "Content chunk: #{chunk.inspect}"
          content_buffer += chunk.dig("delta", "content")
          flush_buffer.call
        else
          Rails.logger.debug "Non-content chunk: #{chunk.inspect}"
        end

        # When finished, broadcast the completion event to the client (e.g. to trigger TTS)
        # (Already done for tool_calls)
        if chunk["finish_reason"].present? && chunk["finish_reason"].length > 0 && chunk["finish_reason"] != "tool_calls"
          flush_buffer.call(force: true) # Force a final flush of the buffer
          broadcast_completion_finished(conversation, message.id)
        end
      rescue StandardError => e
        Rails.logger.error "Error during streaming."
        raise e
      end
    end
  end

  def broadcast_error(message, conversation)
    Rails.logger.debug("Broadcasting error to conversation: #{conversation.id}")
    Turbo::StreamsChannel.broadcast_update_to(
      "#{dom_id(conversation)}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
  end

  def broadcast_completion_finished(conversation, message_id)
    # Send a final message update as workaround for Turbo::Streams::ActionBroadcastJob being processed out-of-order
    # Message.find_by(id: message_id)&.broadcast_updated
    # Rails.logger.debug "Sent final message update for # #{message_id}"

    # Send custom event to the client signalling end of stream (e.g. to trigger TTS)
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
