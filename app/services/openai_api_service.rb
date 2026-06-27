class OpenaiApiService
  # Wrapper around official OpenAI Ruby SDK for LLM completions.
  require "json/repair"
  require "uri"
  include OpenaiResponseHelper
  include OpenaiErrorHelper
  PREFILL_UNSUPPORTED_HOSTS = %w[api.openai.com api.x.ai].freeze
  XAI_HOSTS = %w[api.x.ai].freeze

  # To enable streaming, provide a stream_handler Proc that processes the streamed data as it arrives, including tool calls and content.
  # Each chunk's choices[0] will be passed to the Proc as a JSON object.

  # System prompts are handled as follows:
  # If a custom system prompt is present in the completion messages array, it will be used as the system prompt.
  # If a task system prompt is provided, it will be added to the conversation, along with the base system prompt, teaching principles, and generative guidelines.
  # If neither a system prompt message, nor a task system prompt is provided, the default system prompt will be used (base system prompt + teaching principles).

  def initialize(current_user:, conversation: nil, access_token: nil, base_uri: nil, model: nil, stream_handler: nil, task_system_prompt: nil, enable_tools: false, reasoning_model: false, image_generation: false, log_completion: true)
    # Don't initialize for orphaned student accounts.
    raise OpenAiError, "Students can only use LLMs if they are adopted by a teacher." if current_user.role_student? && current_user.teacher.nil?

    # Raise error if called with any API overrides without all three present
    if base_uri.present? || access_token.present? || model.present?
      unless base_uri.present? && access_token.present? && model.present?
        raise OpenAiError, "If API overrides are given, the base_uri, access_token, and model must all be present."
      end
    end

    @user = current_user
    @conversation = conversation
    @reasoning_model_flag = reasoning_model
    @image_generation_flag = image_generation
    @base_uri = base_uri.presence || current_user.settings&.effective_llm_api_base_uri.presence || default_base_uri
    @access_token = access_token.presence || determine_access_token
    @model = model.presence || determine_model(reasoning_model)
    @client = create_client
    @stream_handler = wrap_stream_handler(stream_handler)
    @tools = determine_tools if enable_tools
    @log_completion = log_completion

    # Start with the full system prompt (base system prompt + teaching principles)
    @system_prompt = "Today's date: #{Time.current.strftime("%B %d, %Y")}\n\n" + Prompt.full_system_prompt(user: current_user)
    # If a task-specific system prompt is provided, append it
    if task_system_prompt
      @system_prompt += "Now, focusing on your current task/role: \n\n" + task_system_prompt
    end
  end

  def complete(messages, response_format: nil, schema: nil, prefill: nil, temperature: 1)
    check_cost_limits
    messages = deep_dup_messages(Array(messages))

    # Inject system prompt to messages if it's not already included
    unless messages.any? { |message| [ message[:role], message["role"] ].compact.first == "system" }
      messages.unshift({ role: "system", content: @system_prompt })
    end

    # Inject prefilled assistant message only for providers that reliably support continuation.
    if prefill && prefill_supported?
      messages << { role: "assistant", content: prefill }
    end

    begin
      request_params = {
        messages: messages,
        model: @model,
        temperature: temperature,
        **(@tools.present? ? { tools: @tools } : {}),
        **(response_format.present? ? { response_format: response_format } : {}),

        # Request usage stats from OpenRouter
        **(@base_uri.include?("openrouter.ai") ? { usage: { include: true } } : {}),
        # Request usage stats when streaming
        **(@stream_handler && !@base_uri.include?("openrouter.ai") ? { stream_options: { include_usage: true } } : {}),

        # Standard-first reasoning controls:
        # - default Chat Completions: reasoning_effort (high for reasoning model, low otherwise)
        # - OpenRouter correction: use reasoning object (+exclude toggle when reasoning model)
        # - xAI correction: omit effort (all-or-nothing reasoning behavior)
        **build_reasoning_params,

        # Set image generation for OpenRouter
        **(@image_generation_flag && @base_uri.include?("openrouter.ai") ? { modalities: [ "image", "text" ] } : {})
      }

      request_options = build_request_options
      request_options_param = request_options.present? ? { request_options: request_options } : {}

      if @stream_handler
        stream = @client.chat.completions.stream_raw(**request_params, **request_options_param)
        stream.each do |chunk|
          @stream_handler.call(normalize_response_hash(chunk), nil)
        end
        @usage = @usage_chunk
        log_completion(resolved_model_name(@finish_chunk&.dig("model")))
        return
      end

      response = @client.chat.completions.create(**request_params, **request_options_param)
      response_hash = normalize_response_hash(response)

      Rails.logger.debug "API response: #{response_hash}"

      # Store the Completion record. Handle streaming and non-streaming cases.
      @usage = response_hash&.dig("usage")
      log_completion(resolved_model_name(response_hash&.dig("model")))

      # If no stream handler was provided, process the response.
      check_for_refusal(response_hash)
      images = response_hash.dig("choices", 0, "message", "images")
      content = response_hash.dig("choices", 0, "message", "content").to_s

      # If image generation was requested and images are present, return the message (with images)
      if @image_generation_flag && images.present?
        return response_hash.dig("choices", 0, "message")
      end

      check_for_blank_content(content)

      # Remove all whitespace from prefill and content so they can be compared
      normalized_prefill = prefill&.gsub(/\s+/, "")
      normalized_content = content.gsub(/\s+/, "")

      # If prefill was used, restore the prefilled portion, unless it's present in the response.
      if prefill_supported? && prefill.present? && !normalized_content.start_with?(normalized_prefill)
        Rails.logger.debug "Response without prefill: #{content}"
        Rails.logger.debug "Prefilling response with: #{prefill}"
        content = prefill + content
      end

      # Return the response content.
      # If JSON requested, parse and validate first.
      if response_format&.dig(:type) == "json_schema" || response_format&.dig(:type) == "json_object"
        parsed_content = parse_JSON(content)
        validate_JSON(parsed_content, schema) if schema.present?
        Rails.logger.debug "Validated JSON content: #{parsed_content}"
        parsed_content
      else
        content
      end
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
      # Re-raise OpenAiError if it's already an OpenAiError, to avoid wrapping it in a generic message
      raise e if e.is_a?(OpenAiError)
      Rails.logger.error "StandardError #{e.inspect}"
      # Rails.logger.error "Trace: #{e.backtrace.join("\n")}"
      raise OpenAiError, "An unexpected error occurred: #{e.message}"
    end # end of begin/rescue/end block
  end

  def list_models
    response = @client.models.list
    models =
      if response.respond_to?(:data)
        response.data
      else
        response_hash = normalize_response_hash(response)
        response_hash["data"] || response_hash[:data]
      end

    Array(models).filter_map do |model|
      if model.respond_to?(:id)
        model.id
      else
        model_hash = normalize_response_hash(model)
        model_hash["id"] || model_hash[:id]
      end
    end
  rescue StandardError => e
    [ "Unable to list models: #{e.message}" ]
  end

  private

  def default_base_uri
    ENV.fetch("OPENAI_API_BASE_URL") { raise "Base URL was neither entered in settings, nor set in ENV variable OPENAI_API_BASE_URL." }
  end

  def determine_access_token
    if codex_provider_base_uri?(@base_uri)
      raise OpenAiError, "ChatGPT Codex provider is Responses-only. Use OpenAI Responses routing for this provider."
    end

    # Prefer the user's own token
    return @user.setting.llm_api_access_token if @user.setting.llm_api_access_token.present?

    # Next, try a shared SupportedApi token that matches the selected base URI
    provider = SupportedApi.selectable_for_teachers.find_by(api_base_uri: @base_uri)
    return provider.api_access_token if provider&.api_access_token.present?

    # Fallback to ENV
    env_token = ENV["OPENAI_API_KEY"].to_s
    return env_token if env_token.present?

    if @user.setting.openai_oauth_connected? && openai_provider_base_uri?(@base_uri)
      raise OpenAiError,
            "OpenAI OAuth is currently only used by Responses API flows. Add an OpenAI API key (personal/shared/ENV) for this path."
    end

    raise OpenAiError, "Access token was neither provided nor set in OPENAI_API_KEY."
  end

  def determine_model(reasoning_model_flag)
    reasoning_model = @user.setting.reasoning_model_name.presence
    nonreasoning_model = @user.setting.llm_model_name.presence || ENV["DEFAULT_MODEL"].presence

    selected_model = if reasoning_model_flag && reasoning_model
      # Use the user's reasoning model
      reasoning_model
    elsif reasoning_model_flag && !reasoning_model
      Rails.logger.info "Reasoning model flag is set, but no reasoning model is configured. Falling back to default model: #{nonreasoning_model}"
      nonreasoning_model
    else
      # Use the user's regular model, or fall back to the default model
      nonreasoning_model
    end

    return selected_model if selected_model.present?

    raise OpenAiError, "No LLM model is configured. Ask your teacher to set one in Settings."
  end

  def create_client
    # Future optimization: Reuse by adding client cache keyed by base_url + api_key, as each client has a connection pool of 99
    OpenAI::Client.new(
      api_key: @access_token,
      base_url: ensure_trailing_slash(@base_uri),
      max_retries: 2,
      timeout: OpenaiClientDefaults.timeout_seconds
    )
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
    headers = attribution_headers.merge(prompt_cache_headers)
    options[:extra_headers] = headers if headers.present?

    options.presence
  end

  def prompt_cache_headers
    return {} unless xai_provider?
    return {} unless @conversation&.id

    { "x-grok-conv-id" => "conversation-#{@conversation.id}" }
  end

  def xai_provider?
    host = URI.parse(@base_uri.to_s).host.to_s.downcase
    XAI_HOSTS.include?(host)
  rescue URI::InvalidURIError
    false
  end

  def deep_dup_messages(messages)
    Array(messages).map { |message| message.is_a?(Hash) ? message.deep_dup : message }
  end

  def ensure_trailing_slash(url)
    return url if url.blank? || url.end_with?("/")
    "#{url}/"
  end

  def check_for_refusal(response)
    return unless response.is_a?(Hash)
    refusal = response.dig("choices", 0, "message", "refusal")
    if refusal.present?
      Rails.logger.warn "LLM refused to fulfill the request with message: #{refusal}"
      raise OpenAiError, "Response refused with message: #{refusal}"
    end
  end

  def check_for_blank_content(content)
    # Rails.logger.debug "Checking content: #{content}"
    # Gemini often returns a blank response.
    if content.blank?
      Rails.logger.warn "Empty response from LLM."
      raise OpenAiError, "Empty response from LLM."
    end
  end

  def parse_JSON(content)
    # LLM may insist on wrapping JSON in a markdown block. Use that if present.
    code_block_json = nil
    code_block_regex = /```(?:json)?\s*([\s\S]*?)\s*```/i
    code_blocks = content.scan(code_block_regex)
    if code_blocks.any?
      code_block_json = code_blocks.last.first.strip
    end
    json_candidates = []
    json_candidates << code_block_json if code_block_json.present?
    json_candidates << content.strip

    balanced_fragment = extract_balanced_json_fragment(content)
    json_candidates << balanced_fragment if balanced_fragment.present?

    # Legacy broad match retained as a last-resort fallback for non-standard outputs.
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

  def prefill_supported?
    host = URI.parse(@base_uri.to_s).host&.downcase
    host.present? && !PREFILL_UNSUPPORTED_HOSTS.include?(host)
  rescue URI::InvalidURIError
    false
  end

  def build_reasoning_params
    host = base_uri_host
    effort = (@reasoning_model_flag ? "high" : "low")
    return {} if host == "api.x.ai"

    if host == "openrouter.ai"
      options = { effort: effort }
      # OpenRouter hides reasoning by default; expose it for reasoning-model calls.
      options[:exclude] = false if @reasoning_model_flag
      return { reasoning: options }
    end

    { reasoning_effort: effort }
  end

  def openai_provider_base_uri?(base_uri)
    URI.parse(base_uri.to_s).host.to_s.downcase == "api.openai.com"
  rescue URI::InvalidURIError
    false
  end

  def codex_provider_base_uri?(base_uri)
    normalized = base_uri.to_s.strip
    normalized = "#{normalized}/" if normalized.present? && !normalized.end_with?("/")
    normalized == SupportedApi::OPENAI_CODEX_BASE_URI
  end

  def base_uri_host
    URI.parse(@base_uri.to_s).host&.downcase
  rescue URI::InvalidURIError
    nil
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
    # Validate the parsed content against the schema
    schemer = JSONSchemer.schema(schema)
    unless schemer.valid?(parsed_content)
      errors = schemer.validate(parsed_content).to_a
      # Retry ?
      raise OpenAiError, "Please try again, or try a more intelligent LLM. Invalid JSON structure: #{errors.map { |e| e['error'] }.join(', ')}"
    end
  end

  # This outer Proc will wrap the provided inner Proc.
  # The outer Proc will handle API-level concerns like checking for refusal, watching for the finish_reason, and logging the Completion.
  # The inner Proc provided should handle application-specic concerns like tool calls and extracting the completion content.
  def wrap_stream_handler(handler)
    # Return if no stream handler is provided, so streaming will be disabled
    return nil unless handler

    unless handler.is_a?(Proc)
      raise ArgumentError, "stream_handler must be a Proc"
    end

    stream_finished = false
    @usage_chunk = {}

    # Return an outer Proc to consume streamed chat completion chunks
    Proc.new do |chunk, _event|
      begin
        Rails.logger.debug "Stream chunk: #{chunk.inspect}"

        # Handle end of stream (but may still have a usage chunk afterward)
        finish_reason = chunk.dig("choices", 0, "finish_reason")
        if finish_reason.present?
          Rails.logger.debug "Streamed response finished with finish_reason: #{finish_reason}"
          stream_finished = true
          @finish_chunk = chunk
        end

        # Handle the final chunk with token usage
        # (Ensure stream is actually finished, since some API may return usage too early)
        # Don't include any essential cleanup logic here, since API may omit 'usage' key (eg. LM Studio)
        if chunk["usage"] && stream_finished
          Rails.logger.debug("Streamed response complete. Usage: #{chunk["usage"]}")
          @usage_chunk = chunk["usage"] # Completion will be created later in the complete method
        end

        choices = chunk&.dig("choices")

        # Check for refusal
        refusal = choices&.dig(0, "delta", "refusal")
        if refusal.present?
          raise OpenAiError, "Response refused with message: #{refusal}"
        end

        # Call the actual handler with the LLM response
        handler.call(choices[0]) if choices.present?

      rescue StandardError => e
        # Handle any errors during processing
        Rails.logger.error "Error processing stream chunk: #{e.message}"
        raise e
      end
    end
  end

  def determine_tools
    ToolCatalogService.new(
      user: @user,
      conversation: @conversation
    ).for_chat_completions
  end

  def check_cost_limits
    LlmUsageAccountingService.enforce_cost_limits!(user: @user, conversation: @conversation)
  end

  def log_completion(model_name)
    return unless @log_completion
    if model_name.blank?
      Rails.logger.error "Skipping completion logging because model was blank."
      return
    end

    Completion.create(
      conversation: @conversation,
      model: model_name,
      api_provider: @base_uri,
      # model_provider: @usage.dig["provider_name"],
      prompt_tokens: @usage&.dig("prompt_tokens")&.to_i,
      prompt_audio_tokens: @usage&.dig("prompt_tokens_details", "audio_tokens")&.to_i,
      cached_tokens: @usage&.dig("prompt_tokens_details", "cached_tokens")&.to_i,
      completion_tokens: @usage&.dig("completion_tokens")&.to_i,
      completion_audio_tokens: @usage&.dig("completion_tokens_details", "audio_tokens")&.to_i,
      reasoning_tokens: @usage&.dig("completion_tokens_details", "reasoning_tokens")&.to_i,
      total_tokens: @usage&.dig("total_tokens")&.to_i,
      total_cost: usage_total_cost(@usage),
      cache_discount: @usage&.dig("cache_discount")&.to_f
    )
  end

  def usage_total_cost(usage)
    LlmUsageAccountingService.usage_total_cost(usage)
  end

  def resolved_model_name(candidate_model)
    candidate_model.to_s.presence || @model.presence
  end
end
