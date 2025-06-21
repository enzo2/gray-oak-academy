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

    # Return a proc that handles the streamed response
    Proc.new do |chunk|
      begin
        # Create the empty message if it doesn't exist yet. This will broadcast the message.
        message ||= conversation.messages.create!(role: "assistant", content: "")

        # Check if the chunk contains tool calls, and accumulate them by index
        if chunk.dig("delta", "tool_calls").present?
          Rails.logger.debug "Tool call chunk: #{chunk.inspect}"
          chunk.dig("delta", "tool_calls").each do |tool_call|
            idx = tool_call["index"] || 0
            tool_calls_buffer[idx] ||= {
              type: tool_call["type"] || "function",
              id: tool_call["id"],
              function: {
                name: tool_call.dig("function", "name"),
                arguments: ""
              }
            }
            # Only set id/name/type if present and not already set
            tool_calls_buffer[idx][:id] ||= tool_call["id"] if tool_call["id"]
            tool_calls_buffer[idx][:type] ||= tool_call["type"] if tool_call["type"]
            tool_calls_buffer[idx][:function][:name] ||= tool_call.dig("function", "name") if tool_call.dig("function", "name")
            # Always append arguments
            tool_calls_buffer[idx][:function][:arguments] += tool_call.dig("function", "arguments") if tool_call.dig("function", "arguments")
          end
        end

        # Finalize and execute tool calls when finish reason indicates tool call completion
        if chunk["finish_reason"] == "tool_calls"
          final_tool_calls = tool_calls_buffer.values.sort_by { |tc| tc[:id].to_s }
          message.update!(tool_calls: final_tool_calls)
          broadcast_completion_finished(conversation, message.id) # Broadcast completion now, since tool may take a while
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
          # For standard content, append the new chunk to the message's content
          Rails.logger.debug "Content chunk: #{chunk.inspect}"
          delta_content = chunk.dig("delta", "content")
          # Updating the message will trigger a turbo stream broadcast to update the view
          message.update!(content: message.content + delta_content)
        else
          Rails.logger.debug "Non-content chunk: #{chunk.inspect}"
        end

        # When finished, broadcast the completion event to the client (e.g. to trigger TTS)
        # (Already done for tool_calls)
        if chunk["finish_reason"].present? && chunk["finish_reason"].length > 0 && chunk["finish_reason"] != "tool_calls"
          broadcast_completion_finished(conversation, message.id)
        end
      rescue StandardError => e
        Rails.logger.error "Error processing stream chunk: #{e.message}"
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
