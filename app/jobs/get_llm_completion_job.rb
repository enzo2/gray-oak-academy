# Job submits a conversation to the OpenRouter API, handles the streamed response, and broadcasts the response to the user.
class GetLlmCompletionJob < ApplicationJob
  queue_as :default
  # retry_on StandardError, wait: 5.seconds, attempts: 2

  # Add a task_system_prompt to the conversation, and it will be appended to the base system prompts.
  # otherwise the default system prompt will be used without any further instructions
  def perform(conversation_id:)
    conversation = Conversation.find(conversation_id)
    user = conversation.user
    client = OpenRouterService.new(
      models: [ user.settings.openrouter_model ],
      access_token: user.settings.openrouter_access_token,
      stream_handler: stream_handler(conversation: conversation),
      task_system_prompt: conversation.task_system_prompt,
      enable_tools: true
    )

    messages = Message.for_completion(conversation.messages) # Get the array of message hashes with roles and content

    client.complete(messages)     # Should return an empty string once completed

  rescue StandardError => e
    Rails.logger.error "Error in GetLLMCompletionJob: #{e.message}"
    broadcast_error("Failed to get LLM completion: #{e.message} \nRetrying...", conversation)
    raise e # This will trigger a retry
  end

  private

  def stream_handler(conversation:)
    # Broadcast the new message to the user so it's ready to be streamed into
    message = conversation.messages.create!(role: "assistant", content: "")
    message.broadcast_created

    # Initialize a buffer to accumulate chunks of tool calls
    tool_call_buffer = { "name": nil, "arguments": "" }

    # Return a proc that handles the streamed response
    Proc.new do |chunk|
      begin
        # Check if the chunk contains tool calls
        if chunk.dig("delta", "tool_calls").present?
          Rails.logger.debug "Tool call chunk: #{chunk.inspect}"
          # Buffer the tool call arguments as they are streamed in
          chunk.dig("delta", "tool_calls").each do |tool_call|
            name = tool_call.dig("function", "name")
            arguments = tool_call.dig("function", "arguments")
            Rails.logger.debug "Processing tool call chunk: name=#{name}, arguments=#{arguments}"
            tool_call_buffer[:name] ||= name if name.present?
            tool_call_buffer[:arguments] += arguments if arguments.present?
          end
        elsif chunk.dig("delta", "content").present?
          Rails.logger.debug "Content chunk: #{chunk.inspect}"
          # For standard content, append the new chunk to the message's content
          delta_content = chunk.dig("delta", "content")
          message.update(content: message.content + delta_content)
        end

        # Finalize and execute tool call when finish reason indicates tool call completion
        if chunk["finish_reason"] == "tool_calls"
          Rails.logger.debug "Tool call arguments buffer: #{tool_call_buffer.inspect}"
          tool_handler = ToolHandlerService.new(conversation: conversation)
          tool_handler.execute_tool_call(tool_call_buffer)
          tool_call_buffer = { "name": nil, "arguments": "" } # Clear buffer for subsequent tool calls
        end
      rescue StandardError => e
        Rails.logger.error "Error processing stream chunk: #{e.message}"
      end
    end
  end

  def broadcast_error(message, conversation)
    Turbo::StreamsChannel.broadcast_update_to(
      "#{dom_id(conversation)}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { type: "error", message: message } }
    )
  end
end
