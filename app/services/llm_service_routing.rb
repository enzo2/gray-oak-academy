class LlmServiceRouting
  require "uri"

  RESPONSES_API_PROVIDER_HOSTS = %w[api.openai.com chatgpt.com openrouter.ai api.x.ai].freeze

  def self.enqueue_completion(conversation:)
    completion_job_class_for(user: conversation.user).perform_later(conversation: conversation)
  end

  def self.completion_job_class_for(user:, base_uri: nil)
    responses_api_routing_enabled_for?(user: user, base_uri: base_uri) ? GetResponsesCompletionJob : GetLlmCompletionJob
  end

  def self.responses_api_routing_enabled_for?(user:, base_uri: nil)
    host = effective_llm_api_host_for(user: user, base_uri: base_uri)
    host.present? && RESPONSES_API_PROVIDER_HOSTS.include?(host)
  end

  def self.build_completion_client(current_user:, conversation: nil, access_token: nil, base_uri: nil, model: nil, stream_handler: nil, task_system_prompt: nil, enable_tools: false, provider_native_tools: nil, flow_tools: nil, reasoning_model: false, image_generation: false, log_completion: true, store: true, previous_response_id: nil, agent_run: false, agent_run_require_stateful: true)
    if responses_api_routing_enabled_for?(user: current_user, base_uri: base_uri)
      OpenaiResponsesService.new(
        current_user: current_user,
        conversation: conversation,
        access_token: access_token,
        base_uri: base_uri,
        model: model,
        stream_handler: stream_handler,
        task_system_prompt: task_system_prompt,
        enable_tools: enable_tools,
        provider_native_tools: provider_native_tools,
        flow_tools: flow_tools,
        reasoning_model: reasoning_model,
        log_completion: log_completion,
        store: store,
        previous_response_id: previous_response_id,
        agent_run: agent_run,
        agent_run_require_stateful: agent_run_require_stateful
      )
    else
      OpenaiApiService.new(
        current_user: current_user,
        conversation: conversation,
        access_token: access_token,
        base_uri: base_uri,
        model: model,
        stream_handler: stream_handler,
        task_system_prompt: task_system_prompt,
        enable_tools: enable_tools,
        reasoning_model: reasoning_model,
        image_generation: image_generation,
        log_completion: log_completion
      )
    end
  end

  def self.complete_structured_output(client:, messages:, response_format:, schema:, prefill: nil)
    params = {
      response_format: response_format,
      schema: schema
    }
    params[:prefill] = prefill if client.is_a?(OpenaiApiService) && prefill.present?
    client.complete(messages, **params)
  end

  def self.effective_llm_api_host_for(user:, base_uri: nil)
    uri = URI.parse(effective_llm_api_base_uri_for(user: user, base_uri: base_uri).to_s)
    uri.host&.downcase
  rescue URI::InvalidURIError
    nil
  end

  def self.effective_llm_api_base_uri_for(user:, base_uri: nil)
    return base_uri if base_uri.present?
    return user.settings.effective_llm_api_base_uri if user.settings.present?

    ENV["OPENAI_API_BASE_URL"].to_s
  end
end
