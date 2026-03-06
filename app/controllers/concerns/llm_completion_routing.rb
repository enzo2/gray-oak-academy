module LlmCompletionRouting
  extend ActiveSupport::Concern

  private

  def enqueue_llm_completion(conversation:)
    LlmServiceRouting.enqueue_completion(conversation: conversation)
  end

  def responses_api_routing_enabled_for?(user)
    LlmServiceRouting.responses_api_routing_enabled_for?(user: user)
  end

  def effective_llm_api_host_for(user)
    LlmServiceRouting.effective_llm_api_host_for(user: user)
  end
end
