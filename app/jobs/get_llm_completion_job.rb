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
      task_system_prompt: conversation.task_system_prompt
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
    # First, create a new empty message for the assistant's response
    messages = []
    message = conversation.messages.create(role: "assistant", content: "")
    message.broadcast_created
    messages << message
    # Handle the streamed response
    Proc.new do |chunk|
      # Append the new chunk to the message's content
      # and broadcast the updated message
      message.update(content: message.content + chunk)
      message.broadcast_updated
    end
  end

  def broadcast_error(message, conversation)
    Turbo::StreamsChannel.broadcast_update_to(
      "#{dom_id(conversation)}_messages",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { type: "error", message: message } }
    )
  end
end
