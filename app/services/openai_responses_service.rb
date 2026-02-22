class OpenaiResponsesService
  # Wrapper around official OpenAI Ruby SDK for the Responses API.
  #
  # Purpose:
  # - Provide a parallel, stateful chat service (Responses API) without touching
  #   existing Chat Completions flows (OpenaiApiService).
  # - Support both streaming and non-streaming with the same interface.
  # - Allow incremental adoption: callers can keep sending full message history,
  #   or use statefulness (store + previous_response_id) and send only new inputs.
  #
  # Important differences vs Chat Completions:
  # - Responses uses "input items" instead of "messages".
  # - Tool calls and tool outputs are distinct item types, linked by call_id.
  # - Structured outputs are configured via text.format, not response_format.
  # - Statefulness is optional; when enabled, you can send only new inputs.
  require "json/repair"
  require "digest"
  require "net/http"
  require "securerandom"
  require "set"
  require "uri"
  include OpenaiResponseHelper
  include OpenaiErrorHelper

  attr_reader :last_response_id, :last_response, :last_response_hash, :previous_response_id, :model, :base_uri
  STATEFUL_RESPONSES_HOSTS = %w[api.openai.com api.x.ai].freeze
  BACKGROUND_RESPONSES_HOSTS = %w[api.openai.com].freeze
  METADATA_RESPONSES_HOSTS = %w[api.openai.com openrouter.ai].freeze
  AGENT_RUN_SYNC_TIMEOUT_SECONDS = 900
  RESPONSES_METADATA_MAX_KEYS = 16
  RESPONSES_METADATA_MAX_KEY_LENGTH = 64
  RESPONSES_METADATA_MAX_STRING_LENGTH = 512

  def self.base_uri_host(base_uri)
    URI.parse(base_uri.to_s).host.to_s.downcase.presence
  rescue URI::InvalidURIError
    nil
  end

  def self.stateful_supported_base_uri?(base_uri)
    host = base_uri_host(base_uri)
    host.present? && STATEFUL_RESPONSES_HOSTS.include?(host)
  end

  def self.background_supported_base_uri?(base_uri)
    host = base_uri_host(base_uri)
    host.present? && BACKGROUND_RESPONSES_HOSTS.include?(host)
  end

  def self.metadata_supported_base_uri?(base_uri)
    host = base_uri_host(base_uri)
    host.present? && METADATA_RESPONSES_HOSTS.include?(host)
  end

  # OpenAI + xAI support Responses state chaining via previous_response_id.
  def stateful_supported?
    self.class.stateful_supported_base_uri?(@base_uri)
  end

  def background_supported?
    self.class.background_supported_base_uri?(@base_uri)
  end

  def metadata_supported?
    self.class.metadata_supported_base_uri?(@base_uri)
  end

  # Initialize a new Responses client.
  #
  # - current_user: required (for settings, access token, model selection)
  # - conversation: optional, used for cost tracking + tool scoping
  # - stream_handler: optional Proc; will receive each streamed event (hash)
  # - task_system_prompt: optional; appended to base system prompt
  # - enable_tools: enables tools from Tool model (converted to Responses format)
  # - provider_native_tools: tools native to the Responses API provider (e.g. [{ type: "web_search" }])
  # - flow_tools: internal app-defined tools for specialized sub-agent flows
  # - store: when true, Responses API stores state, enabling previous_response_id
  # - previous_response_id: optional; allows chaining stateful Responses calls
  # - agent_run: when true, use AppSetting background agent provider/model config
  # - agent_run_require_stateful: when true, fail fast unless provider supports stateful runs
  def initialize(current_user:, conversation: nil, access_token: nil, base_uri: nil, model: nil, stream_handler: nil, task_system_prompt: nil, enable_tools: false, provider_native_tools: nil, flow_tools: nil, reasoning_model: false, log_completion: true, store: true, previous_response_id: nil, agent_run: false, agent_run_require_stateful: true)
    # Don't initialize for orphaned student accounts.
    raise OpenAiError, "Students can only use LLMs if they are adopted by a teacher." if current_user.role_student? && current_user.teacher.nil?

    @agent_run = agent_run

    @user = current_user
    @conversation = conversation
    @reasoning_model_flag = reasoning_model

    if @agent_run
      config = resolve_agent_run_config(
        base_uri_override: base_uri,
        access_token_override: access_token,
        model_override: model,
        require_stateful: agent_run_require_stateful
      )
      @base_uri = config.fetch(:base_uri)
      @access_token = config.fetch(:access_token)
      @model = config.fetch(:model)
    else
      # Raise error if called with any API overrides without all three present.
      if base_uri.present? || access_token.present? || model.present?
        unless base_uri.present? && access_token.present? && model.present?
          raise OpenAiError, "If API overrides are given, the base_uri, access_token, and model must all be present."
        end
      end

      @base_uri = base_uri.presence || current_user.settings&.effective_llm_api_base_uri.presence || default_base_uri
      @access_token = access_token.presence || determine_access_token
      @model = model.presence || determine_model(reasoning_model)
    end
    @client = create_client
    # We pass raw streaming events (converted to hashes) to the handler.
    # The handler decides how to render/broadcast output to the UI.
    @stream_handler = wrap_stream_handler(stream_handler)

    @tools = []
    @tools.concat(determine_tools) if enable_tools
    @tools.concat(normalize_flow_tools(flow_tools))
    @tools.concat(normalize_provider_native_tools(provider_native_tools))
    @tools = @tools.uniq { |tool| tool_dedup_key(tool) }.presence
    @log_completion = log_completion
    @store = store.nil? ? true : store
    @active_store = @store
    @previous_response_id = resolve_previous_response_id(previous_response_id)
    @agent_run_contexts_by_run_id = {}
    @agent_run_context_by_response_id = {}
    @agent_run_active_run_id = nil
    @response_overview_log_state = {}
    @response_summary_log_state = {}

    # Start with the full system prompt (base system prompt + teaching principles)
    @system_prompt = "Today's date: #{Time.current.strftime("%B %d, %Y")}\n\n" + Prompt.full_system_prompt(user: current_user)
    # If a task-specific system prompt is provided, append it
    if task_system_prompt
      @system_prompt += "Now, focusing on your current task/role: \n\n" + task_system_prompt
    end
  end

  # Main entrypoint.
  #
  # - messages: Chat Completions-style array (role/content/etc). Converted to Responses input items.
  # - input: raw Responses input items (skips conversion).
  # - instructions: optional explicit top-level guidance; usually omit and rely on
  #   default developer input prompt injection.
  # - response_format/schema: supports structured output via JSON schema (text.format).
  # - store/previous_response_id: stateful context chaining (useful for chats).
  #
  # For stateful chat flows:
  # - Call once with store: true (default) and no previous_response_id.
  # - Reuse the same instance and it will set previous_response_id automatically
  #   based on the last response id, allowing you to send only new inputs.
  def complete(messages = nil, input: nil, instructions: nil, response_format: nil, schema: nil, temperature: 1, store: nil, previous_response_id: nil, include: nil, background: false, metadata: nil, max_output_tokens: nil, max_tool_calls: nil, parallel_tool_calls: nil, tool_choice: nil, reasoning: nil)
    sanitized_metadata = sanitize_responses_metadata(metadata)
    agent_run_context = prepare_agent_run_context(
      background: background,
      metadata: metadata,
      messages: messages,
      input: input
    )

    with_openai_error_handling do
      check_cost_limits
      format_type = response_format_type(response_format)

      input_items = input.presence || build_input_from_messages(messages)
      raise OpenAiError, "Input is required for Responses API." if input_items.blank?
      state_params = build_state_params(store: store, previous_response_id: previous_response_id)
      @active_store = stateful_supported? ? state_params.fetch(:store, @store) : false
      chained_state = state_params[:previous_response_id].present?
      include_fields = build_include_fields(include: include, state_params: state_params)

      if instructions.present?
        if chained_state
          raise OpenAiError,
                "Explicit instructions are not allowed with previous_response_id. Use developer messages for stateful follow-up requests."
        end
      else
        input_items = prepend_default_developer_input(input_items, messages: messages, chained_state: chained_state)
      end

      reasoning_options = build_reasoning_options(reasoning)

      sync_background_fallback = agent_run_synchronous_background?(background: background)
      request_background = background && !sync_background_fallback && background_supported?
      request_metadata = metadata_supported? ? sanitized_metadata : nil
      if sync_background_fallback
        Rails.logger.info(
          "Responses background mode requested for agent run; using synchronous execution for provider #{@base_uri}."
        )
      elsif background && !request_background
        Rails.logger.warn(
          "Responses background mode not supported for provider #{@base_uri}. Falling back to synchronous create."
        )
      end
      if metadata.present? && request_metadata.blank?
        Rails.logger.warn(
          "Responses metadata is not supported for provider #{@base_uri}. Omitting metadata."
        )
      end

      request_params = {
        model: @model,
        input: input_items,
        temperature: temperature,
        **(instructions.present? ? { instructions: instructions } : {}),
        **(@tools.present? ? { tools: @tools } : {}),
        **(include_fields.present? ? { include: include_fields } : {}),
        **(request_background ? { background: true } : {}),
        **(request_metadata.present? ? { metadata: request_metadata } : {}),
        **(max_output_tokens.present? ? { max_output_tokens: max_output_tokens } : {}),
        **(max_tool_calls.present? ? { max_tool_calls: max_tool_calls } : {}),
        **(parallel_tool_calls.present? ? { parallel_tool_calls: parallel_tool_calls } : {}),
        **(tool_choice.present? ? { tool_choice: tool_choice } : {}),
        **(reasoning_options.present? ? { reasoning: reasoning_options } : {}),
        **build_text_params(response_format)
      }

      request_params.merge!(state_params) if state_params.present?

      request_options = build_request_options
      request_options_param = request_options.present? ? { request_options: request_options } : {}
      log_request_summary(request_params: request_params, request_options: request_options, streaming: @stream_handler.present?)

      if @stream_handler
        # Streaming: Responses SDK yields a stream of typed events.
        # We normalize each event to a hash and forward it to the handler.
        # When the "response.completed" event arrives, we log usage and update
        # previous_response_id for stateful follow-ups.
        stream = @client.responses.stream(**request_params, **request_options_param)
        stream.each do |event|
          handle_stream_event(event)
          @stream_handler.call(normalize_response_hash(event))
        end
        return
      end

      response = @client.responses.create(**request_params, **request_options_param)
      response_hash = normalize_response_hash(response)

      set_last_response(response_hash, response)
      log_response_summary(response_hash, phase: "submit")
      log_response_overview(response_hash, phase: "submit")
      record_agent_run_submitted(response_hash: response_hash, context: agent_run_context)

      # Background run submission may return queued/in_progress with no output;
      # callers should poll/retrieve using response_id.
      if background
        return response_hash
      end

      log_completion(response_hash)

      check_for_refusal(response_hash)
      content = extract_output_text(response_hash)
      check_for_blank_content(content, response_hash: response_hash)

      if %w[json_schema json_object].include?(format_type)
        parsed_content = parse_JSON(content)
        validate_JSON(parsed_content, schema) if schema.present?
        Rails.logger.debug "Validated JSON content: #{parsed_content}"
        parsed_content
      else
        content
      end
    end
  rescue OpenAiError => e
    record_agent_run_failed(error_message: e.message)
    raise
  end

  # Fetch a previously-created response by id.
  def retrieve_response(response_id, include: nil)
    with_openai_error_handling do
      raise OpenAiError, "response_id is required." if response_id.blank?

      response =
        if include.present?
          retrieve_response_with_include(response_id, include: include)
        else
          request_options = build_request_options
          request_options_param = request_options.present? ? { request_options: request_options } : {}
          @client.responses.retrieve(response_id, **request_options_param)
        end

      response_hash = normalize_response_hash(response)
      set_last_response(response_hash, response)
      log_response_summary(response_hash, phase: "poll")
      log_response_overview(response_hash, phase: "poll")
      maybe_record_agent_run_terminal(response_hash)
      response_hash
    end
  rescue OpenAiError => e
    record_agent_run_failed(error_message: e.message)
    raise
  end

  # Poll a background response until terminal status or timeout.
  # Returns the final response hash.
  def wait_for_response(response_id, timeout_seconds: 600, poll_interval_seconds: 2, include: nil)
    if (cached_response = terminal_cached_response_for(response_id))
      status = cached_response["status"].to_s
      if status == "completed"
        log_completion(cached_response)
        maybe_record_agent_run_terminal(cached_response)
      else
        maybe_record_agent_run_terminal(cached_response)
      end
      return cached_response
    end

    deadline = Time.current + timeout_seconds

    loop do
      response_hash = retrieve_response(response_id, include: include)
      status = response_hash["status"].to_s

      if status == "completed"
        log_completion(response_hash)
        maybe_record_agent_run_terminal(response_hash)
        return response_hash
      end

      if %w[failed cancelled canceled incomplete].include?(status)
        maybe_record_agent_run_terminal(response_hash)
        return response_hash
      end

      if Time.current >= deadline
        raise OpenAiError, "Background response timed out after #{timeout_seconds} seconds."
      end

      sleep(poll_interval_seconds)
    end
  rescue OpenAiError => e
    record_agent_run_failed(error_message: e.message)
    raise
  end

  def cancel_response(response_id)
    with_openai_error_handling(unexpected_message: "Failed to cancel response") do
      raise OpenAiError, "response_id is required." if response_id.blank?

      request_options = build_request_options
      request_options_param = request_options.present? ? { request_options: request_options } : {}
      response = @client.responses.cancel(response_id, **request_options_param)
      response_hash = normalize_response_hash(response)
      log_response_summary(response_hash, phase: "cancel")
      log_response_overview(response_hash, phase: "cancel")
      maybe_record_agent_run_terminal(response_hash)
      response_hash
    end
  rescue OpenAiError => e
    record_agent_run_failed(error_message: e.message)
    raise
  end

  def output_text(response_hash = nil)
    target = response_hash || normalize_response_hash(@last_response)
    extract_output_text(target)
  end

  private

  def agent_run_synchronous_background?(background:)
    background && @agent_run && !background_supported?
  end

  def terminal_cached_response_for(response_id)
    return nil if response_id.blank? || @last_response_hash.blank?
    return nil unless @last_response_hash["id"].to_s == response_id.to_s

    status = @last_response_hash["status"].to_s
    return nil unless terminal_response_status?(status)

    @last_response_hash
  end

  def terminal_response_status?(status)
    %w[completed failed cancelled canceled incomplete].include?(status.to_s)
  end

  def with_openai_error_handling(unexpected_message: "An unexpected error occurred")
    yield
  rescue OpenAI::Errors::BadRequestError, OpenAI::Errors::UnprocessableEntityError, OpenAI::Errors::ConflictError => e
    error_message = extract_openai_error_message(e)
    Rails.logger.error "BadRequestError: #{e.message}: #{error_message}"
    raise OpenAiError, "The server rejected the request. #{error_message}"
  rescue OpenAI::Errors::AuthenticationError, OpenAI::Errors::PermissionDeniedError => e
    error_message = extract_openai_error_message(e)
    Rails.logger.error "Auth error: #{e.message}: #{error_message}"
    raise OpenAiError, "The access key was unauthorized. Ask teacher to check it."
  rescue OpenAI::Errors::NotFoundError => e
    error_message = extract_openai_error_message(e)
    Rails.logger.error "NotFoundError #{e.message}: #{error_message}"
    raise OpenAiError, "The requested service was not found. Details: #{error_message}"
  rescue OpenAI::Errors::RateLimitError => e
    error_message = extract_openai_error_message(e)
    Rails.logger.error "RateLimitError #{e.message}: #{error_message}"
    raise OpenAiError, "Too many requests. Details: #{error_message}"
  rescue OpenAI::Errors::APITimeoutError => e
    Rails.logger.error "APITimeoutError #{e.message}"
    raise OpenAiError, "LLM did not respond in time. Ask your teacher to try a different model."
  rescue OpenAI::Errors::APIConnectionError => e
    Rails.logger.error "APIConnectionError #{e.message}"
    raise OpenAiError, "The connection to the LLM provider failed. Please try again."
  rescue OpenAI::Errors::ConversionError => e
    error_message = extract_openai_error_message(e)
    Rails.logger.error "ConversionError #{e.message}: #{error_message}"
    raise OpenAiError, "The client encountered an error. Details: #{error_message}"
  rescue OpenAI::Errors::InternalServerError, OpenAI::Errors::APIStatusError => e
    error_message = extract_openai_error_message(e)
    Rails.logger.error "APIStatusError #{e.message}: #{error_message}"
    raise OpenAiError, "The server encountered an error. Details: #{error_message}"
  rescue OpenAI::Errors::APIError => e
    error_message = extract_openai_error_message(e)
    Rails.logger.error "APIError #{e.message}: #{error_message}"
    raise OpenAiError, "The server encountered an error. Details: #{error_message}"
  rescue StandardError => e
    raise e if e.is_a?(OpenAiError)

    Rails.logger.error "StandardError #{e.inspect}"
    raise OpenAiError, "#{unexpected_message}: #{e.message}"
  end

  def default_base_uri
    ENV.fetch("OPENAI_API_BASE_URL") { raise "Base URL was neither entered in settings, nor set in ENV variable OPENAI_API_BASE_URL." }
  end

  def determine_access_token
    # Prefer the user's own token
    return @user.setting.llm_api_access_token if @user.setting.llm_api_access_token.present?

    # Next, try a shared SupportedApi token that matches the selected base URI
    provider = SupportedApi.selectable_for_teachers.find_by(api_base_uri: @base_uri)
    return provider.api_access_token if provider&.api_access_token.present?

    # Fallback to ENV
    ENV.fetch("OPENAI_API_KEY") { raise "Access token was neither provided nor set in OPENAI_API_KEY." }
  end

  def determine_model(reasoning_model_flag)
    reasoning_model = @user.setting.reasoning_model_name.presence
    nonreasoning_model = @user.setting.llm_model_name.presence || ENV["DEFAULT_MODEL"].presence

    selected_model = if reasoning_model_flag && reasoning_model
      reasoning_model
    elsif reasoning_model_flag && !reasoning_model
      Rails.logger.info "Reasoning model flag is set, but no reasoning model is configured. Falling back to default model: #{nonreasoning_model}"
      nonreasoning_model
    else
      nonreasoning_model
    end

    return selected_model if selected_model.present?

    raise OpenAiError, "No LLM model is configured. Ask your teacher to set one in Settings."
  end

  def resolve_agent_run_config(base_uri_override:, access_token_override:, model_override:, require_stateful:)
    app_setting = AppSetting.settings
    unless app_setting
      raise OpenAiError, "Background agent runs are not configured. Ask a superuser to set App Settings."
    end

    model_name = model_override.to_s.presence || app_setting.openai_agent_model.to_s.presence
    if model_name.blank?
      raise OpenAiError, "Background agent runs model is not configured. Set it in App Settings."
    end

    provider = resolve_agent_run_provider(app_setting: app_setting, base_uri_override: base_uri_override)
    unless provider
      raise OpenAiError, "Background agent runs provider is not configured. Select OpenAI or xAI with a shared token in App Settings."
    end

    provider_base_uri = provider.api_base_uri.to_s
    access_token = access_token_override.to_s.presence || provider.api_access_token.to_s.presence
    unless access_token
      raise OpenAiError, "Background agent runs provider key is missing. Add a shared key for #{provider_base_uri} in LLM APIs."
    end

    if require_stateful && !self.class.stateful_supported_base_uri?(provider_base_uri)
      raise OpenAiError,
            "Background agent runs provider #{provider_base_uri} does not support required stateful Responses behavior. Select OpenAI or xAI in App Settings."
    end

    {
      base_uri: provider_base_uri,
      access_token: access_token,
      model: model_name
    }
  end

  def resolve_agent_run_provider(app_setting:, base_uri_override:)
    if base_uri_override.present?
      return SupportedApi.find_responses_agent_selectable_by_base_uri(base_uri_override)
    end

    app_setting.openai_agent_supported_api
  end

  def create_client
    # Future optimization: Reuse by adding client cache keyed by base_url + api_key, as each client has a connection pool of 99
    OpenAI::Client.new(
      api_key: @access_token,
      base_url: ensure_trailing_slash(@base_uri),
      max_retries: 2,
      timeout: client_timeout_seconds
    )
  end

  def client_timeout_seconds
    return [ OpenaiClientDefaults.timeout_seconds, AGENT_RUN_SYNC_TIMEOUT_SECONDS ].max if @agent_run

    OpenaiClientDefaults.timeout_seconds
  end

  def attribution_headers
    return {} unless @base_uri.include?("openrouter.ai")
    {
      "X-Title" => "Gray Oak Academy",
      "HTTP-Referer" => Rails.env.production? ? "https://#{ENV.fetch('APP_HOST')}" : nil
    }.compact
  end

  def build_request_options
    options = {}
    headers = attribution_headers
    options[:extra_headers] = headers if headers.present?

    options.presence
  end

  def build_reasoning_options(reasoning)
    options = reasoning.is_a?(Hash) ? reasoning.deep_dup.deep_symbolize_keys : {}
    options[:effort] = @reasoning_model_flag ? "high" : "low" if options[:effort].blank?

    # xAI rejects the Responses reasoning effort parameter for some models.
    options.delete(:effort) if self.class.base_uri_host(@base_uri) == "api.x.ai"

    # OpenRouter defaults to hidden reasoning; request summaries/tokens unless caller opted out.
    if @reasoning_model_flag && @base_uri.include?("openrouter.ai") && !options.key?(:exclude)
      options[:exclude] = false
    end

    options.presence
  end

  # Build Responses "text.format" for structured output.
  # Accepts the same response_format structure used by OpenaiApiService
  # and adapts it to Responses API shape.
  def build_text_params(response_format)
    return {} unless response_format.present?

    type = response_format_type(response_format)
    return {} if type.blank?

    if type.to_s == "json_schema"
      json_schema = response_format[:json_schema] || response_format["json_schema"] || {}
      format = {
        type: "json_schema",
        name: json_schema[:name] || json_schema["name"],
        strict: json_schema[:strict] || json_schema["strict"],
        schema: json_schema[:schema] || json_schema["schema"]
      }.compact
    else
      format = { type: type }
    end

    { text: { format: format } }
  end

  def response_format_type(response_format)
    return nil if response_format.blank?
    type = response_format[:type] || response_format["type"]
    type&.to_s
  end

  # NOTE: openai-ruby 0.45.0 sends a scalar query value for include when using
  # responses.retrieve, which OpenAI may reject as invalid_type.
  # We work around this by issuing a direct GET with include[] query keys.
  def retrieve_response_with_include(response_id, include:)
    uri = URI.join(ensure_trailing_slash(@base_uri), "responses/#{response_id}")
    include_pairs = Array(include).map { |value| [ "include[]", value.to_s ] }
    uri.query = URI.encode_www_form(include_pairs) if include_pairs.present?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"

    request = Net::HTTP::Get.new(uri.request_uri)
    request["Authorization"] = "Bearer #{@access_token}"
    request["Content-Type"] = "application/json"
    attribution_headers.each { |key, value| request[key] = value }

    response = http.request(request)
    body = response.body.to_s
    parsed = body.present? ? JSON.parse(body) : {}

    unless response.is_a?(Net::HTTPSuccess)
      message = parsed.dig("error", "message").presence || "HTTP #{response.code}"
      raise OpenAiError, "The server rejected the request. #{message}"
    end

    parsed
  end

  # Statefulness:
  # - store: when true, Response is stored server-side
  # - previous_response_id: allows chaining without sending full history
  def build_state_params(store:, previous_response_id:)
    return {} unless stateful_supported?

    effective_store = store.nil? ? @store : store
    effective_previous = previous_response_id.presence || @previous_response_id || conversation_previous_response_id

    params = { store: effective_store }
    if effective_store && effective_previous.present?
      params[:previous_response_id] = effective_previous
    end
    params
  end

  def build_include_fields(include:, state_params:)
    include_fields = Array(include).flatten.compact.map(&:to_s).reject(&:blank?)
    include_fields << "reasoning.encrypted_content" if stateless_reasoning_include_required?(state_params: state_params)
    include_fields.uniq.presence
  end

  # For stateless runs (including providers that do not support state chaining),
  # request encrypted reasoning so it can be replayed on subsequent tool-call turns.
  def stateless_reasoning_include_required?(state_params:)
    effective_store = state_params.key?(:store) ? state_params[:store] : false
    !effective_store
  end

  # For non-chained requests, prepend a developer message so prompt context
  # is carried in input items rather than top-level instructions.
  def prepend_default_developer_input(input_items, messages:, chained_state:)
    return input_items if chained_state
    return input_items if contains_developer_or_system_input_item?(input_items)

    prompt_text = developer_prompt_text(messages)
    return input_items if prompt_text.blank?

    [ { "role" => "developer", "content" => prompt_text } ] + Array(input_items)
  end

  def developer_prompt_text(messages)
    system_messages = Array(messages).select { |m| hash_value(m, :role).to_s == "system" }
    if system_messages.present?
      system_messages.map { |m| hash_value(m, :content).to_s }.join("\n\n")
    else
      @system_prompt
    end
  end

  def contains_developer_or_system_input_item?(input_items)
    Array(input_items).any? do |item|
      role = hash_value(item, :role).to_s
      role == "developer" || role == "system"
    end
  end

  # Convert Chat Completions-style messages into Responses input items.
  # We skip system messages here because they are converted to a developer
  # input item (or explicit instructions when provided).
  def build_input_from_messages(messages)
    raise OpenAiError, "Messages are required for Responses API." if messages.blank?

    Array(messages).flat_map do |message|
      build_input_item_from_message(message)
    end.compact
  end

  # Convert a single message into one or more Responses input items.
  # - tool responses become function_call_output items
  # - assistant tool_calls become function_call items
  # - standard user/assistant messages become {role, content}
  def build_input_item_from_message(message)
    role = hash_value(message, :role).to_s

    if role == "system"
      return nil
    end

    if role == "tool"
      tool_call_id = hash_value(message, :tool_call_id)
      return nil if tool_call_id.blank?

      output = normalize_function_call_output(hash_value(message, :content))
      output_id = function_call_output_id(message, tool_call_id, output)
      return {
        "type" => "function_call_output",
        "id" => output_id,
        "call_id" => tool_call_id,
        "output" => output
      }
    end

    items = []
    content = normalize_message_content(hash_value(message, :content))
    items << { "role" => role, "content" => content } if content.present?

    tool_calls = hash_value(message, :tool_calls)
    reasoning_items = build_reasoning_items(hash_value(message, :reasoning_details))
    if role == "assistant" && tool_calls.present? && reasoning_items.present?
      items.concat(reasoning_items)
    end

    if role == "assistant" && tool_calls.present?
      items.concat(build_function_call_items(tool_calls))
    end

    items
  end

  def build_reasoning_items(reasoning_details)
    Array(reasoning_details).filter_map do |detail|
      next unless detail.is_a?(Hash)

      encrypted_content = hash_value(detail, :encrypted_content).to_s
      summary = normalize_reasoning_summary(hash_value(detail, :summary))
      id = hash_value(detail, :id).to_s
      status = hash_value(detail, :status).to_s
      # Responses providers reject bare reasoning IDs. Replay only when
      # the turn includes concrete reasoning payload (encrypted or summary).
      next if encrypted_content.blank? && summary.blank?

      {
        "type" => "reasoning",
        "id" => id.presence,
        "status" => status.presence,
        "summary" => summary.presence,
        "encrypted_content" => encrypted_content.presence
      }.compact
    end
  end

  def normalize_reasoning_summary(summary)
    case summary
    when String
      text = summary.strip
      return [] if text.blank?

      [ { "type" => "summary_text", "text" => text } ]
    when Array
      summary.filter_map { |entry| normalize_reasoning_summary_entry(entry) }
    when Hash
      entry = normalize_reasoning_summary_entry(summary)
      entry.present? ? [ entry ] : []
    else
      []
    end
  end

  def normalize_reasoning_summary_entry(entry)
    return nil unless entry.is_a?(Hash)

    type = hash_value(entry, :type).to_s.presence || "summary_text"
    text = hash_value(entry, :text).to_s
    text = hash_value(entry, :summary_text).to_s if text.blank?
    text = text.strip
    return nil if text.blank?

    { "type" => type, "text" => text }
  end

  # Convert multi-part message content into Responses input items:
  # - text -> input_text
  # - image_url -> input_image
  # - input_audio -> input_audio
  def normalize_message_content(content)
    return content if content.is_a?(String)
    return nil if content.nil?

    parts = content.is_a?(Array) ? content : [ content ]

    parts.map do |part|
      next part unless part.is_a?(Hash)

      case hash_value(part, :type)
      when "text"
        { "type" => "input_text", "text" => hash_value(part, :text) }
      when "image_url"
        image_url = part.dig(:image_url, :url) || part.dig("image_url", "url")
        detail = part.dig(:image_url, :detail) || part.dig("image_url", "detail") || "auto"
        { "type" => "input_image", "image_url" => image_url, "detail" => detail }
      when "input_audio"
        { "type" => "input_audio", "input_audio" => hash_value(part, :input_audio) }
      else
        part
      end
    end
  end

  # Convert Chat Completions tool calls into Responses function_call items.
  # Responses uses "call_id" rather than "id".
  def build_function_call_items(tool_calls)
    Array(tool_calls).filter_map do |tool_call|
      function = hash_value(tool_call, :function) || {}
      call_id = hash_value(tool_call, :call_id) || hash_value(tool_call, :id)
      name = hash_value(function, :name)
      next if call_id.blank? || name.blank?

      arguments = hash_value(function, :arguments) || ""
      function_call_id = hash_value(tool_call, :response_item_id) || hash_value(tool_call, :response_function_call_id)
      function_call_id ||= hash_value(tool_call, :id)
      function_call_id ||= "fc_#{Digest::SHA256.hexdigest("#{call_id}:#{name}:#{arguments}")[0, 24]}"

      {
        "type" => "function_call",
        "id" => function_call_id,
        "call_id" => call_id,
        "name" => name,
        "arguments" => arguments
      }
    end
  end

  def wrap_stream_handler(handler)
    return nil unless handler
    raise ArgumentError, "stream_handler must be a Proc" unless handler.is_a?(Proc)
    handler
  end

  # Handle stream events. We care primarily about response completion so we can
  # log usage and update previous_response_id for stateful follow-ups.
  def handle_stream_event(event)
    return unless event.is_a?(OpenAI::Streaming::ResponseCompletedEvent)

    response_hash = normalize_response_hash(event.response)
    set_last_response(response_hash, event.response)
    log_response_summary(response_hash, phase: "stream_completed")
    log_completion(response_hash)
  end

  # Record the last response so callers can chain stateful requests.
  # When store is enabled, we treat the last response id as previous_response_id.
  def set_last_response(response_hash, response_obj)
    @last_response = response_obj
    @last_response_hash = response_hash
    @last_response_id = response_hash["id"]
    update_conversation_state if @active_store && @last_response_id.present?
  end

  # Extract plain text from the Responses "output" array.
  # This mirrors the chat-completions "message.content" path.
  def extract_output_text(response_hash)
    output_items = response_hash["output"] || []
    text_parts = []

    output_items.each do |item|
      next unless item["type"].to_s == "message"

      Array(item["content"]).each do |content|
        next unless content["type"].to_s == "output_text"
        text_parts << content["text"].to_s
      end
    end

    text_parts.join
  end

  # Responses represent refusals as output content items of type "refusal".
  def check_for_refusal(response_hash)
    output_items = response_hash["output"] || []
    output_items.each do |item|
      next unless item["type"].to_s == "message"

      Array(item["content"]).each do |content|
        next unless content["type"].to_s == "refusal"
        refusal = content["refusal"] || content["text"]
        raise OpenAiError, "Response refused with message: #{refusal}"
      end
    end
  end

  def check_for_blank_content(content, response_hash:)
    return unless content.blank? && !response_contains_tool_calls?(response_hash)

    Rails.logger.warn(
      "LLM returned empty text content. response_id=#{response_hash['id']} status=#{response_hash['status']}"
    )
  end

  def response_contains_tool_calls?(response_hash)
    Array(response_hash["output"]).any? do |item|
      item_type = item["type"].to_s
      item_type == "function_call" || item_type.end_with?("_call")
    end
  end

  def parse_JSON(content)
    code_block_json = nil
    code_block_regex = /```(?:json)?\s*([\s\S]*?)\s*```/i
    code_blocks = content.scan(code_block_regex)
    code_block_json = code_blocks.last.first.strip if code_blocks.any?
    json_candidates = []
    json_candidates << code_block_json if code_block_json.present?
    json_candidates << content.strip

    balanced_fragment = extract_balanced_json_fragment(content)
    json_candidates << balanced_fragment if balanced_fragment.present?

    broad_match = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
    json_candidates << broad_match if broad_match.present?

    json_candidates = json_candidates.compact.uniq
    raise OpenAiError, "No valid JSON found in the LLM response." if json_candidates.blank?

    parse_errors = []

    json_candidates.each do |json_content|
      Rails.logger.info "Extracted JSON candidate: #{json_content}"
      begin
        return JSON.parse(json_content)
      rescue JSON::ParserError => e
        parse_errors << e
      end
    end

    json_candidates.each do |json_content|
      begin
        Rails.logger.info "Invalid JSON in LLM response, attempting to repair"
        repaired_content = JSON.repair(json_content)
        Rails.logger.info "Repaired JSON: #{repaired_content}"
        return JSON.parse(repaired_content)
      rescue JSON::JSONRepairError, JSON::ParserError => e
        parse_errors << e
      end
    end

    raise OpenAiError, "Invalid JSON in LLM response, unable to repair: #{parse_errors.last&.message || 'Unknown parsing error'}"
  end

  def extract_balanced_json_fragment(text)
    return nil if text.blank?

    text.length.times do |start_idx|
      char = text[start_idx]
      next unless char == "{" || char == "["

      fragment = balanced_json_from_index(text, start_idx)
      next unless fragment.present?

      begin
        JSON.parse(fragment)
        return fragment
      rescue JSON::ParserError
        next
      end
    end

    nil
  end

  def balanced_json_from_index(text, start_idx)
    stack = []
    in_string = false
    escaped = false

    (start_idx...text.length).each do |idx|
      ch = text[idx]

      if in_string
        if escaped
          escaped = false
        elsif ch == "\\"
          escaped = true
        elsif ch == "\""
          in_string = false
        end
        next
      end

      case ch
      when "\""
        in_string = true
      when "{", "["
        stack << ch
      when "}"
        return nil if stack.empty? || stack.last != "{"
        stack.pop
        return text[start_idx..idx] if stack.empty?
      when "]"
        return nil if stack.empty? || stack.last != "["
        stack.pop
        return text[start_idx..idx] if stack.empty?
      end
    end

    nil
  end

  def validate_JSON(parsed_content, schema)
    schemer = JSONSchemer.schema(schema)
    unless schemer.valid?(parsed_content)
      errors = schemer.validate(parsed_content).to_a
      raise OpenAiError, "Please try again, or try a more intelligent LLM. Invalid JSON structure: #{errors.map { |e| e['error'] }.join(', ')}"
    end
  end

  def determine_tools
    ToolCatalogService.new(
      user: @user,
      conversation: @conversation
    ).for_responses
  end

  def normalize_provider_native_tools(provider_native_tools)
    Array(provider_native_tools).filter_map do |tool|
      case tool
      when String, Symbol
        { "type" => tool.to_s }
      when Hash
        normalized = tool.deep_stringify_keys
        next nil if normalized["type"].blank?
        if normalized["type"] == "function"
          Rails.logger.warn("OpenaiResponsesService: function tools are not provider-native; pass them via flow_tools.")
          next nil
        end

        normalized
      else
        nil
      end
    end
  end

  def normalize_flow_tools(flow_tools)
    Array(flow_tools).filter_map do |tool|
      case tool
      when Hash
        normalized = tool.deep_stringify_keys
        normalized["type"].present? ? normalized : nil
      else
        nil
      end
    end
  end

  def check_cost_limits
    daily_budget = @user.daily_budget
    max_chat_cost = AppSetting.settings&.max_chat_cost

    return unless daily_budget.present? || max_chat_cost.present?

    if daily_budget.present?
      daily_spend = Completion.where(user: @user).in_date_range(Date.current, Date.current).sum(:total_cost)
      if daily_spend >= daily_budget
        in_active_lesson = @conversation&.lesson_progress.present? && !@conversation.lesson_progress.completed?
        lesson_overage_limit = daily_budget * 1.25
        over_lesson_allowance = daily_spend >= lesson_overage_limit

        if !in_active_lesson || over_lesson_allowance
          message = if in_active_lesson && over_lesson_allowance
            "Daily API usage budget exceeded even after lesson allowance."
          else
            "Daily API usage budget of has been exceeded. Please try again tomorrow."
          end
          notify_admins_of_limit(message)
          raise OpenAiError, message
        end
      end
    end

    if @conversation && max_chat_cost.present?
      chat_spend = Completion.where(conversation: @conversation).sum(:total_cost)
      if chat_spend >= max_chat_cost
        message = "This chat has exceeded the maximum cost limit. Please start a new one."
        notify_admins_of_limit(message)
        raise OpenAiError, message
      end
    end
  end

  def notify_admins_of_limit(reason)
    superuser_ids = User.role_superuser.pluck(:id)
    return if superuser_ids.empty?

    Rails.event.notify(Events::UserLimitExceeded.new(
      recipient_ids: superuser_ids,
      link: Rails.application.routes.url_helpers.admin_student_path(@user),
      user_name: @user.name,
      user_id: @user.id,
      reason: reason
    ))
  rescue StandardError => e
    Rails.logger.error "Failed to notify admins of limit: #{e.message}"
  end

  # Store usage/cost info. Responses usage fields differ from Chat Completions,
  # so we normalize to the Completion model's columns here.
  def log_completion(response_hash)
    return unless @log_completion

    usage = response_hash["usage"] || {}
    prompt_tokens = usage["input_tokens"] || usage["prompt_tokens"]
    completion_tokens = usage["output_tokens"] || usage["completion_tokens"]
    cached_tokens = usage.dig("input_tokens_details", "cached_tokens") || usage.dig("prompt_tokens_details", "cached_tokens")
    reasoning_tokens = usage.dig("output_tokens_details", "reasoning_tokens") || usage.dig("completion_tokens_details", "reasoning_tokens")
    model_name = resolved_model_name(response_hash)

    if model_name.blank?
      Rails.logger.error "Skipping completion logging because model was blank. response_id=#{response_hash['id']}"
      return
    end

    Completion.create(
      conversation: @conversation,
      user: @user,
      model: model_name,
      api_provider: @base_uri,
      prompt_tokens: prompt_tokens&.to_i,
      cached_tokens: cached_tokens&.to_i,
      completion_tokens: completion_tokens&.to_i,
      reasoning_tokens: reasoning_tokens&.to_i,
      total_tokens: usage["total_tokens"]&.to_i,
      total_cost: usage["cost"]&.to_f,
      cache_discount: usage["cache_discount"]&.to_f
    )
  end

  # Decide which previous_response_id to use:
  # - explicit param wins
  # - otherwise, use conversation state only if provider/model match
  # - require store to be enabled (Responses requires store:true for chaining)
  def resolve_previous_response_id(explicit_previous)
    return explicit_previous if explicit_previous.present?
    return nil unless @store
    return nil unless stateful_supported?

    conversation_previous_response_id
  end

  # Persist the latest response id to the conversation so the next call
  # can chain via previous_response_id without re-sending full history.
  def update_conversation_state
    return unless stateful_supported?

    @previous_response_id = @last_response_id
    return unless @conversation

    # Avoid unnecessary writes.
    return if @conversation.responses_previous_id == @last_response_id &&
              @conversation.responses_provider == @base_uri &&
              @conversation.responses_model == @model

    @conversation.update!(
      responses_previous_id: @last_response_id,
      responses_provider: @base_uri,
      responses_model: @model
    )
  rescue StandardError => e
    Rails.logger.error "Failed to update conversation responses state: #{e.message}"
  end

  def ensure_trailing_slash(url)
    return url if url.blank? || url.end_with?("/")
    "#{url}/"
  end

  def base_uri_host
    self.class.base_uri_host(@base_uri)
  end

  def hash_value(hash, key)
    return nil unless hash.respond_to?(:[])
    hash[key] || hash[key.to_s]
  end

  def sanitize_responses_metadata(metadata)
    return metadata unless metadata.is_a?(Hash)

    metadata.each_with_object({}) do |(key, value), sanitized|
      next if sanitized.size >= RESPONSES_METADATA_MAX_KEYS

      sanitized_key = key.to_s.first(RESPONSES_METADATA_MAX_KEY_LENGTH)
      next if sanitized_key.blank?

      sanitized_value = sanitize_responses_metadata_value(value)
      next if sanitized_value.nil?

      sanitized[sanitized_key] = sanitized_value
    end
  end

  def sanitize_responses_metadata_value(value)
    case value
    when nil
      nil
    when String
      truncate_metadata_string(value)
    else
      serialized =
        begin
          value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value.to_s
        rescue StandardError
          value.to_s
        end

      truncate_metadata_string(serialized)
    end
  end

  def truncate_metadata_string(value)
    string_value = value.to_s
    return string_value if string_value.length <= RESPONSES_METADATA_MAX_STRING_LENGTH

    string_value[0, RESPONSES_METADATA_MAX_STRING_LENGTH]
  end

  def normalize_function_call_output(content)
    return "" if content.nil?
    return content if content.is_a?(String)

    normalized = normalize_message_content(content)
    return normalized if normalized.is_a?(Array)

    normalized.to_s
  end

  def function_call_output_id(message, tool_call_id, output)
    explicit = hash_value(message, :id)
    return explicit.to_s if explicit.present?

    "fco_#{Digest::SHA256.hexdigest("#{tool_call_id}:#{output}")[0, 24]}"
  end

  def tool_dedup_key(tool)
    hash = if tool.respond_to?(:deep_stringify_keys)
      tool.deep_stringify_keys
    else
      tool
    end
    return hash.to_s unless hash.is_a?(Hash)

    type = hash["type"].to_s
    name = hash["name"].presence || hash.dig("function", "name").presence
    return "#{type}|#{name}" if name.present?

    "#{type}|#{hash.to_json}"
  end

  def conversation_previous_response_id
    return nil unless @conversation
    return nil unless @conversation.responses_state_matches?(provider: @base_uri, model: @model)

    @conversation.responses_previous_id
  end

  def prepare_agent_run_context(background:, metadata:, messages:, input:)
    return nil unless agent_run_logging_enabled?(background: background)

    meta = metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
    explicit_run_id = meta["run_id"].to_s.presence
    existing = current_agent_run_context
    existing = @agent_run_contexts_by_run_id[explicit_run_id] || existing if explicit_run_id.present?
    run_id = explicit_run_id || existing[:run_id] || SecureRandom.uuid

    existing_for_run = @agent_run_contexts_by_run_id[run_id] || existing
    derived_prompt = derive_prompt_from_request(messages: messages, input: input)
    same_run = existing_for_run[:run_id].to_s == run_id.to_s
    prompt = if same_run
      existing_for_run[:prompt].presence ||
        derived_prompt.presence ||
        "Background Responses run"
    else
      derived_prompt.presence ||
        "Background Responses run"
    end

    context = {
      run_id: run_id,
      source: meta["source"].presence || meta["run_type"].presence || existing_for_run[:source] || "background",
      prompt: prompt,
      started_at: existing_for_run[:started_at] || Time.current,
      tool_calls: same_run ? Array(existing_for_run[:tool_calls]).dup : [],
      response_metrics: same_run ? (existing_for_run[:response_metrics] || {}).deep_dup : {},
      terminal_logged: same_run ? existing_for_run[:terminal_logged] : false,
      metadata_version: meta["metadata_version"].presence || existing_for_run[:metadata_version],
      phase: meta["phase"].presence || existing_for_run[:phase]
    }

    persist_agent_run_context(context)
    context
  end

  def agent_run_logging_enabled?(background:)
    background && @agent_run && @stream_handler.nil? && @conversation.nil?
  end

  def agent_run_log_service
    @agent_run_log_service ||= AgentRunLogService.new
  end

  def current_agent_run_context
    return {} if @agent_run_active_run_id.to_s.blank?

    @agent_run_contexts_by_run_id[@agent_run_active_run_id] || {}
  end

  def persist_agent_run_context(context)
    return unless context.is_a?(Hash)

    run_id = context[:run_id].to_s
    return if run_id.blank?

    @agent_run_contexts_by_run_id[run_id] = context
    @agent_run_active_run_id = run_id
  end

  def agent_run_context_for_response(response_hash)
    response_id = response_hash.is_a?(Hash) ? response_hash["id"].to_s : ""
    if response_id.present?
      run_id = @agent_run_context_by_response_id[response_id].to_s
      context = @agent_run_contexts_by_run_id[run_id]
      return context if context.present?
    end

    context = current_agent_run_context
    context.present? ? context : nil
  end

  def record_agent_run_submitted(response_hash:, context:)
    return unless context.present?

    response_id = response_hash["id"].to_s
    return if response_id.blank?

    context[:response_id] = response_id
    context[:phase] = context[:phase].presence || "submitted"
    context[:terminal_logged] = false
    persist_agent_run_context(context)
    @agent_run_context_by_response_id[response_id] = context[:run_id].to_s
    agent_run_log_service.record_submitted(
      run_id: context[:run_id],
      response_id: response_id,
      teacher: @user,
      model: resolved_model_name(response_hash),
      provider_base_uri: @base_uri,
      source: context[:source],
      prompt: context[:prompt],
      metadata_version: context[:metadata_version],
      phase: context[:phase]
    )
  rescue StandardError => e
    Rails.logger.error "Failed to record submitted agent run #{context[:run_id]}: #{e.message}"
  end

  def resolved_model_name(response_hash = nil)
    response_model = response_hash.is_a?(Hash) ? response_hash["model"].presence : nil
    response_model || @model.presence
  end

  def maybe_record_agent_run_terminal(response_hash)
    context = agent_run_context_for_response(response_hash)
    return unless context.present?
    return if context[:terminal_logged]

    status = response_hash["status"].to_s
    case status
    when "completed"
      return if response_contains_tool_calls?(response_hash)

      agent_run_log_service.record_completed(
        run_id: context[:run_id],
        response_id: response_hash["id"].to_s.presence || context[:response_id],
        response_hash: response_hash,
        started_at: context[:started_at],
        metrics: aggregate_agent_run_metrics(context, response_hash: response_hash),
        tool_calls: context[:tool_calls]
      )
      log_tool_call_sequence(context)
      context[:phase] = "completed"
      context[:terminal_logged] = true
      persist_agent_run_context(context)
    when "failed", "cancelled", "canceled", "incomplete"
      record_agent_run_failed(
        error_message: "Run status: #{status}. #{extract_agent_run_error(response_hash)}",
        response_hash: response_hash
      )
    end
  rescue StandardError => e
    Rails.logger.error "Failed to record terminal agent run status: #{e.message}"
  end

  def record_agent_run_failed(error_message:, response_hash: nil)
    context = response_hash.present? ? agent_run_context_for_response(response_hash) : current_agent_run_context
    return unless context.present?
    return if context[:terminal_logged]

    agent_run_log_service.record_failed(
      run_id: context[:run_id],
      response_id: context[:response_id],
      response_hash: response_hash || {},
      started_at: context[:started_at] || Time.current,
      error_message: error_message,
      metrics: aggregate_agent_run_metrics(context, response_hash: response_hash),
      tool_calls: context[:tool_calls]
    )
    log_tool_call_sequence(context)
    context[:phase] = "failed"
    context[:terminal_logged] = true
    persist_agent_run_context(context)
  rescue StandardError => e
    Rails.logger.error "Failed to record failed agent run #{context[:run_id]}: #{e.message}"
  end

  def log_response_overview(response_hash, phase:)
    context = agent_run_context_for_response(response_hash)
    return unless context.present?

    response_id = response_hash["id"].to_s
    status = response_hash["status"].to_s
    output_items = Array(response_hash["output"])
    cache_key = response_id.presence || "unknown_response"
    tool_calls = extract_response_tool_calls(output_items, response_id: cache_key)
    track_tool_calls(context, tool_calls)

    output_counts = output_items.each_with_object(Hash.new(0)) { |item, memo| memo[item["type"].to_s] += 1 }
    tool_signature = tool_calls.map { |tool_call| "#{tool_call[:name]}(#{tool_call[:call_id]})" }.join("|")
    state_key = [ status, output_counts.to_a.sort_by(&:first), tool_signature ]
    return if @response_overview_log_state[cache_key] == state_key

    @response_overview_log_state[cache_key] = state_key
    track_response_metrics(context, cache_key, output_items)

    output_summary = output_counts.map { |type, count| "#{type}=#{count}" }.join(", ")
    tool_call_summary = if tool_calls.present?
      preview = tool_calls.first(8).map { |tool_call| "#{tool_call[:name]}(#{tool_call[:call_id]})" }.join(", ")
      tool_calls.size > 8 ? "#{preview}, ...(+#{tool_calls.size - 8} more)" : preview
    else
      "none"
    end

    Rails.logger.info(
      "Responses run overview phase=#{phase} run_id=#{context[:run_id]} source=#{context[:source]} " \
      "response_id=#{cache_key} status=#{status.presence || 'unknown'} " \
      "output_items=#{output_items.size} output_types=#{output_summary.presence || 'none'} " \
      "tool_calls=#{tool_call_summary}"
    )
  end

  def log_request_summary(request_params:, request_options:, streaming:)
    run_context = current_agent_run_context
    run_id_log = run_context.is_a?(Hash) ? run_context[:run_id].to_s.presence : nil
    input_items = Array(request_params[:input])
    tools = Array(request_params[:tools])
    input_type_counts = input_items.each_with_object(Hash.new(0)) do |item, memo|
      memo[input_item_type(item)] += 1
    end
    input_summary = input_type_counts.map { |type, count| "#{type}=#{count}" }.join(", ")
    tool_summary = tools.first(8).map { |tool| summarize_tool(tool) }.join(", ")
    tool_summary = "#{tool_summary}, ...(+#{tools.size - 8} more)" if tools.size > 8

    Rails.logger.debug(
      "Responses request run_id=#{run_id_log || 'none'} model=#{@model} provider=#{@base_uri} streaming=#{streaming} " \
      "store=#{request_params[:store].inspect} previous_response_id=#{request_params[:previous_response_id].presence || 'none'} " \
      "input_items=#{input_items.size} input_types=#{input_summary.presence || 'none'} " \
      "tools=#{tools.size} tool_names=#{tool_summary.presence || 'none'} " \
      "background=#{request_params[:background] ? true : false} " \
      "response_format=#{request_params.dig(:text, :format, :type).presence || 'text'} " \
      "extra_headers=#{Array(request_options&.dig(:extra_headers)&.keys).join(',').presence || 'none'}"
    )
    log_request_input_items(input_items)
  end

  def log_response_summary(response_hash, phase:)
    response_id = response_hash["id"].to_s.presence || "unknown"
    status = response_hash["status"].to_s.presence || "unknown"
    run_context = agent_run_context_for_response(response_hash)
    run_id_log = run_context.is_a?(Hash) ? run_context[:run_id].to_s.presence : nil
    output_items = Array(response_hash["output"])
    output_counts = output_items.each_with_object(Hash.new(0)) { |item, memo| memo[item["type"].to_s] += 1 }
    tool_calls = output_counts.fetch("function_call", 0)
    usage = response_hash["usage"] || {}

    state_key = [
      phase,
      status,
      output_counts.to_a.sort_by(&:first),
      usage["input_tokens"],
      usage["output_tokens"],
      usage["total_tokens"]
    ]
    cache_key = "#{phase}:#{response_id}"
    return if @response_summary_log_state[cache_key] == state_key

    @response_summary_log_state[cache_key] = state_key
    output_summary = output_counts.map { |type, count| "#{type}=#{count}" }.join(", ")

    Rails.logger.debug(
      "Responses response phase=#{phase} run_id=#{run_id_log || 'none'} response_id=#{response_id} status=#{status} " \
      "output_items=#{output_items.size} output_types=#{output_summary.presence || 'none'} " \
      "function_calls=#{tool_calls} input_tokens=#{usage['input_tokens']} " \
      "output_tokens=#{usage['output_tokens']} total_tokens=#{usage['total_tokens']}"
    )
  end

  def log_request_input_items(input_items)
    return if input_items.empty?
    return unless Rails.logger.debug?

    input_items.each_with_index do |item, index|
      payload =
        begin
          JSON.pretty_generate(item)
        rescue StandardError
          item.inspect
        end
      Rails.logger.debug("Responses request input_item[#{index}]=#{payload}")
    end
  end

  def input_item_type(item)
    return "unknown" unless item.is_a?(Hash)

    type = item["type"] || item[:type]
    return type.to_s if type.present?

    role = item["role"] || item[:role]
    role.present? ? "message:#{role}" : "unknown"
  end

  def summarize_tool(tool)
    return "unknown" unless tool.is_a?(Hash)

    type = tool["type"].presence || tool[:type].presence || "unknown"
    name = tool["name"] || tool[:name] || tool.dig("function", "name") || tool.dig(:function, :name)
    name.present? ? "#{type}:#{name}" : type.to_s
  end

  def extract_response_tool_calls(output_items, response_id:)
    Array(output_items).filter_map do |item|
      next unless item["type"].to_s == "function_call"
      argument_metadata = tool_call_argument_metadata(item["arguments"])

      {
        response_id: response_id.to_s,
        call_id: (item["call_id"] || item["id"]).to_s,
        name: item["name"].to_s,
        arguments_preview: argument_metadata[:arguments_preview],
        argument_fingerprint: argument_metadata[:argument_fingerprint]
      }
    end
  end

  def track_tool_calls(context, tool_calls)
    return if tool_calls.blank?

    context[:tool_calls] ||= []
    seen = context[:tool_calls].map { |tool_call| [ tool_call[:call_id], tool_call[:name] ] }.to_set
    tool_calls.each do |tool_call|
      key = [ tool_call[:call_id], tool_call[:name] ]
      next if seen.include?(key)

      context[:tool_calls] << tool_call
      seen << key
    end
  end

  def track_response_metrics(context, response_key, output_items)
    context[:response_metrics] ||= {}
    context[:response_metrics][response_key] = response_output_metrics(output_items)
  end

  def aggregate_agent_run_metrics(context, response_hash: nil)
    tracked_metrics = Array((context[:response_metrics] || {}).values)
    fallback_metrics = response_output_metrics(Array((response_hash || {})["output"]))

    metrics = {
      assistant_turns: tracked_metrics.sum { |m| m[:assistant_turns].to_i },
      tool_call_count: tracked_metrics.sum { |m| m[:tool_call_count].to_i },
      tool_turn_count: tracked_metrics.sum { |m| m[:tool_turn_count].to_i },
      reasoning_item_count: tracked_metrics.sum { |m| m[:reasoning_item_count].to_i },
      output_item_count: tracked_metrics.sum { |m| m[:output_item_count].to_i }
    }

    return fallback_metrics if tracked_metrics.empty?

    metrics
  end

  def response_output_metrics(output_items)
    items = Array(output_items)

    {
      assistant_turns: items.count { |item| item["type"].to_s == "message" },
      tool_call_count: items.count { |item| tool_call_item?(item["type"]) },
      tool_turn_count: items.any? { |item| tool_call_item?(item["type"]) } ? 1 : 0,
      reasoning_item_count: items.count { |item| item["type"].to_s == "reasoning" },
      output_item_count: items.size
    }
  end

  def tool_call_item?(type)
    type = type.to_s
    type == "function_call" || type.end_with?("_call")
  end

  def tool_call_argument_metadata(raw_arguments)
    raw = raw_arguments.is_a?(String) ? raw_arguments : raw_arguments.to_json
    raw = raw.to_s
    return { arguments_preview: nil, argument_fingerprint: nil } if raw.blank?

    parsed = parse_tool_call_arguments(raw)
    normalized = parsed.present? ? normalize_tool_call_argument_value(parsed).to_json : raw.squish

    {
      arguments_preview: tool_call_argument_preview(parsed, raw),
      argument_fingerprint: Digest::SHA256.hexdigest(normalized)
    }
  end

  def parse_tool_call_arguments(raw_arguments)
    JSON.parse(raw_arguments)
  rescue JSON::ParserError
    begin
      JSON.parse(JSON.repair(raw_arguments))
    rescue JSON::ParserError, JSON::JSONRepairError
      nil
    end
  end

  def normalize_tool_call_argument_value(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) do |key, sorted|
        sorted[key.to_s] = normalize_tool_call_argument_value(value[key])
      end
    when Array
      value.map { |item| normalize_tool_call_argument_value(item) }
    else
      value
    end
  end

  def tool_call_argument_preview(parsed_arguments, raw_arguments)
    return raw_arguments.to_s.squish.truncate(220) unless parsed_arguments.is_a?(Hash)

    if parsed_arguments["query"].present?
      return "query=#{parsed_arguments['query'].to_s.squish.truncate(180)}"
    end

    if parsed_arguments["urls"].is_a?(Array)
      first_url = parsed_arguments["urls"].first.to_s
      return "urls=#{parsed_arguments['urls'].size} first=#{first_url.squish.truncate(140)}"
    end

    if parsed_arguments["uri"].present?
      return "uri=#{parsed_arguments['uri'].to_s.squish.truncate(180)}"
    end

    parsed_arguments.to_json.squish.truncate(220)
  end

  def log_tool_call_sequence(context)
    tool_calls = Array(context[:tool_calls])
    return if tool_calls.empty?

    sequence = tool_calls.map { |tool_call| "#{tool_call[:name]}(#{tool_call[:call_id]})" }.join(" -> ")
    Rails.logger.info(
      "Responses run tool call sequence run_id=#{context[:run_id]} source=#{context[:source]} " \
      "count=#{tool_calls.size} sequence=#{sequence.truncate(2000)}"
    )
  end

  def extract_agent_run_error(response_hash)
    error = response_hash["error"]
    return "Unknown error" if error.blank?
    return error.to_s unless error.is_a?(Hash)

    error["message"].presence || error["code"].presence || "Unknown error"
  end

  def derive_prompt_from_request(messages:, input:)
    messages_preview = extract_text_from_items(Array(messages))
    return messages_preview if messages_preview.present?

    input_preview = extract_text_from_items(Array(input))
    return input_preview if input_preview.present?

    nil
  end

  def extract_text_from_items(items)
    text = items.filter_map do |item|
      if item.is_a?(Hash)
        role = hash_value(item, :role).to_s
        next nil if role.present? && role != "user" && role != "developer" && role != "system"

        content = hash_value(item, :content)
        extract_text_from_content(content)
      else
        item.to_s
      end
    end.join("\n").squish

    text.presence
  end

  def extract_text_from_content(content)
    case content
    when String
      content
    when Array
      content.filter_map { |part| extract_text_from_content(part) }.join(" ")
    when Hash
      hash_value(content, :text) || hash_value(content, :input_text) || hash_value(content, :output_text)
    else
      content.to_s
    end
  end
end
