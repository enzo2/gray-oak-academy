# Job submits a conversation to the LLM API wrapper service, handles the streamed response, and broadcasts the response to the user.
class GetLlmCompletionJob < ApplicationJob
  include ActionView::RecordIdentifier
  queue_as :default

  # Add a task_system_prompt to the conversation, and it will be appended to the base system prompts.
  # Otherwise, the default system prompt will be used without any further instructions.

  def perform(conversation_id:)
    conversation = Conversation.find(conversation_id)
    user = conversation.user

    # With ruby-openai gem (also supports openrouter):
    client = OpenaiApiService.new(
      current_user: user,
      stream_handler: stream_handler(conversation: conversation),
      task_system_prompt: conversation.task_system_prompt,
      enable_tools: true
    )

    messages = Message.for_completion_with_images(conversation.messages) # Get the array of message hashes with roles and content

    client.complete(messages)     # Should return an empty string once completed, since we used streaming.
  rescue OpenAiError => e
    Rails.logger.error "Faraday::ResourceNotFound caused by: #{e.message}"
    broadcast_error("LLM Error. Ask your teacher to try a different model. Error: #{e.message}", conversation)
    raise
  rescue Faraday::TimeoutError => e
    Rails.logger.error "Faraday::TimeoutError #{e.message}"
    broadcast_error("LLM did not respond in time. Ask your teacher to try a different model.", conversation)
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

    # Initialize a buffer to accumulate chunks of tool calls
    tool_call_buffer = { "name": nil, "arguments": "" }

    # Return a proc that handles the streamed response
    Proc.new do |chunk|
      begin
        message ||= conversation.messages.create!(role: "assistant", content: "") # Create the empty message if it doesn't exist yet

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
        end

        if chunk["finish_reason"] == "tool_calls"
          # Finalize and execute tool call when finish reason indicates tool call completion
          Rails.logger.debug "Calling tool with arguments: #{tool_call_buffer.inspect}"
          tool_handler = ToolHandlerService.new(conversation: conversation, message: message)
          tool_handler.execute_tool_call(tool_call_buffer)
          tool_call_buffer = { "name": nil, "arguments": "" } # Clear buffer for subsequent tool calls
        elsif chunk.dig("delta", "content").present?
          # For standard content, append the new chunk to the message's content
          Rails.logger.debug "Content chunk: #{chunk.inspect}"
          delta_content = chunk.dig("delta", "content")
          # Updating the message will trigger a turbo stream broadcast to update the view
          message.update(content: message.content + delta_content)
        else
          Rails.logger.debug "Non-content chunk: #{chunk.inspect}"
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
end
