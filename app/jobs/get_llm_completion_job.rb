# Job submits a conversation to the LLM API wrapper service, handles the streamed response, and broadcasts the response to the user.
class GetLlmCompletionJob < ApplicationJob
  include ActionView::RecordIdentifier
  include ApplicationHelper
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation:) { conversation }, duration: 1.minutes

  # Add a task_system_prompt to the conversation, and it will be appended to the base system prompts.
  # Otherwise, the default system prompt will be used without any further instructions.

  def perform(conversation:)
    user = conversation.user
    include_images = conversation.image_input_supported?

    client = OpenaiApiService.new( # Uses ruby-openai gem (not just for OpenAI, supports any OpenAI-compatible API):
      current_user: user,
      stream_handler: stream_handler(conversation: conversation),
      task_system_prompt: conversation.task_system_prompt,
      enable_tools: true,
      conversation: conversation
    )

    # Get the array of message hashes with roles and content
    messages = Message.for_completion(
      messages: conversation.messages,
      audio: conversation.audio_input_permitted?,
      images: include_images
    )

    client.complete(messages)     # Should return an empty string once completed, since we used streaming.

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
    # Buffer for reasoning_details from thinking models (OpenRouter), accumulated by index
    reasoning_details_buffer = {}
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
            idx = (tool_call.dig("index") || 0).to_i
            # Initialize the tool call entry in the buffer if this is the first chunk for this tool call
            tool_calls_buffer[idx] ||= {
              type: tool_call.dig("type") || "function",
              # Gemini OpenAI Compatibility API bug workaround - it gives an empty string as ID, but needs one later or gives a 400 error
              id: tool_call["id"].blank? ? "call_#{SecureRandom.alphanumeric(24)}" : tool_call["id"],
              function: {
                name: tool_call.dig("function", "name"),
                arguments: "" # Initialize as empty string, will be updated with actual arguments
              }
            }
            # Preserve any provider-specific metadata required for subsequent requests (e.g. Gemini `thought_signature`).
            tool_calls_buffer[idx].merge!(extract_tool_call_metadata(tool_call))
            if tool_call["function"].is_a?(Hash)
              tool_calls_buffer[idx][:function].merge!(extract_function_metadata(tool_call["function"]))
            end
            # id/type/name are supposed to be set in the first chunk, so we won't change them.
            # Append arguments
            tool_calls_buffer[idx][:function][:arguments] += tool_call.dig("function", "arguments") if tool_call.dig("function", "arguments")
          end
        end

        # Capture reasoning_details from thinking models
        # These come in fragments across multiple chunks, so we accumulate them by index like tool_calls
        if chunk.dig("delta", "reasoning_details").present?
          chunk.dig("delta", "reasoning_details").each do |detail|
            idx = (detail["index"] || 0).to_i

            # Initialize this reasoning block if this is the first chunk for this index
            reasoning_details_buffer[idx] ||= {
              "type" => detail["type"],
              "index" => idx,
              "format" => detail["format"]
            }

            # Merge/accumulate text fields (e.g., summary, text, etc.)
            detail.each do |key, value|
              next if [ "type", "index", "format" ].include?(key)

              if value.is_a?(String)
                # Concatenate string fields
                reasoning_details_buffer[idx][key] ||= ""
                reasoning_details_buffer[idx][key] += value
              else
                # For non-string fields, use last value
                reasoning_details_buffer[idx][key] = value
              end
            end
          end
        end

        if chunk.dig("delta", "content").to_s.length > 0
          # For standard content, append the new chunk to the buffer
          Rails.logger.debug "Content chunk: #{chunk.inspect}"
          content_buffer += chunk.dig("delta", "content")
          flush_buffer.call
        else
          Rails.logger.debug "Non-content chunk: #{chunk.inspect}"
        end

        # Check if the chunk contains images, and accumulate them
        # Todo

        # Finalize and execute tool calls when finish reason indicates tool call completion
        if chunk["finish_reason"].present? && chunk["finish_reason"].length > 0
          # When finished, broadcast the completion event to the client (e.g. to trigger TTS)
          flush_buffer.call(force: true)

          # Save reasoning_details if present (for thinking model continuity across tool calls)
          if reasoning_details_buffer.present?
            message ||= conversation.messages.build(role: "assistant")
            # Convert hash to array, sorted by index
            message.reasoning_details = reasoning_details_buffer.sort_by { |idx, _| idx }.map { |_, detail| detail }
            message.save! if message.persisted? # Save immediately if already persisted, otherwise will be saved below
          end

          if tool_calls_buffer.present?
            message ||= conversation.messages.build(role: "assistant") # Create message if not already created (i.e. if there was no content)
            final_tool_calls = tool_calls_buffer.sort_by { |idx, _tc| idx }.map { |_idx, tc| tc } # Order by the index
            message.update!(tool_calls: final_tool_calls) # Add tool calls to the message
            message_id = check_for_blank_response(message, conversation)
            broadcast_completion_finished(conversation, message_id) # Broadcast completion now, since tool may take a while
            Rails.logger.debug "Tool call streamed. Calling tool(s): #{final_tool_calls.inspect}"
            tool_handler = ToolHandlerService.new(conversation: conversation, message: message)
            tool_handler.execute_tool_calls(final_tool_calls)
            tool_calls_buffer.clear # Clear buffer for subsequent tool calls
          else
            message_id = check_for_blank_response(message, conversation)
            broadcast_completion_finished(conversation, message_id)
          end
        end
      rescue StandardError => e
        Rails.logger.error "Error during streaming."
        raise e
      end
    end
  end

  # OpenRouter (Gemini) may return tool call metadata that must be preserved in subsequent requests,
  # like `thought_signature`. Keep these keys, but exclude standard fields we handle explicitly.
  def extract_tool_call_metadata(tool_call)
    return {} unless tool_call.is_a?(Hash)

    excluded = %w[index type id function]
    tool_call.each_with_object({}) do |(k, v), acc|
      next if excluded.include?(k.to_s)
      next if v.nil? || (v.respond_to?(:empty?) && v.empty?)
      acc[k.to_sym] = v
    end
  end

  def extract_function_metadata(function_hash)
    return {} unless function_hash.is_a?(Hash)

    excluded = %w[name arguments]
    function_hash.each_with_object({}) do |(k, v), acc|
      next if excluded.include?(k.to_s)
      next if v.nil? || (v.respond_to?(:empty?) && v.empty?)
      acc[k.to_sym] = v
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
    # Placeholder may have been added for the assistant reply. Remove it.
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

  def check_for_blank_response(message, conversation)
    content_blank = effectively_blank_text?(message&.content) # includes ZWSP
    tools_blank = message&.tool_calls.nil? || message.tool_calls.empty?
    if message.nil? || (content_blank && tools_blank) # No support for audio-only responses currently
      previous_message = if message&.persisted?
        conversation.messages.where.not(id: message.id).reorder(created_at: :desc).first
      else
        conversation.messages.reorder(created_at: :desc).first
      end
      Rails.logger.debug "Previous message: #{previous_message.id} #{previous_message&.role} #{previous_message&.content}"

      # Only log/broadcast unexpected blanks (e.g., not following tool use).
      if unexpected_blank_response?(previous_message)
        Rails.logger.warn("Unexpected blank response from LLM")
        broadcast_warning("LLM returned an empty response.", conversation)
      else
        Rails.logger.debug("Blank response from LLM (acceptable)")
      end

      unless message&.persisted?
        Turbo::StreamsChannel.broadcast_remove_to("#{dom_id(conversation)}", target: "new_message")
      end
    end
    message&.id
  end

  def unexpected_blank_response?(previous_message)
    # Normal to have a blank response if after a tool response.
    return false if previous_message&.role_tool?
    return false if previous_message&.role_assistant? && previous_message.tool_calls.present?
    true
  end
end
