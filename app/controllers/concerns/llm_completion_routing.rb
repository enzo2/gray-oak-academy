module LlmCompletionRouting
  extend ActiveSupport::Concern

  RESPONSES_API_PROVIDER_HOSTS = %w[api.openai.com openrouter.ai].freeze

  private

  def enqueue_llm_completion(conversation:)
    if responses_api_routing_enabled_for?(conversation.user)
      GetResponsesCompletionJob.perform_later(conversation: conversation)
    else
      GetLlmCompletionJob.perform_later(conversation: conversation)
    end
  end

  def responses_api_routing_enabled_for?(user)
    host = effective_llm_api_host_for(user)
    host.present? && RESPONSES_API_PROVIDER_HOSTS.include?(host)
  end

  def effective_llm_api_host_for(user)
    return user.settings.effective_llm_api_host if user.settings.present?

    uri = URI.parse(ENV["OPENAI_API_BASE_URL"].to_s)
    uri.host&.downcase
  rescue URI::InvalidURIError
    nil
  end
end
