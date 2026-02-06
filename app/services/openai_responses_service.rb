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
  require "net/http"
  require "uri"
  include OpenaiResponseHelper
  include OpenaiErrorHelper

  attr_reader :last_response_id, :last_response, :previous_response_id

  # Initialize a new Responses client.
  #
  # - current_user: required (for settings, access token, model selection)
  # - conversation: optional, used for cost tracking + tool scoping
  # - stream_handler: optional Proc; will receive each streamed event (hash)
  # - task_system_prompt: optional; appended to base system prompt
  # - enable_tools: enables tools from Tool model (converted to Responses format)
  # - native_tools: native Responses tools (e.g. [{ type: "web_search" }])
  # - store: when true, Responses API stores state, enabling previous_response_id
  # - previous_response_id: optional; allows chaining stateful Responses calls
  def initialize(current_user:, conversation: nil, access_token: nil, base_uri: nil, model: nil, stream_handler: nil, task_system_prompt: nil, enable_tools: false, native_tools: nil, reasoning_model: false, log_completion: true, store: true, previous_response_id: nil)
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
    @base_uri = base_uri.presence || current_user.settings.llm_api_base_uri.presence || default_base_uri
    @access_token = access_token.presence || determine_access_token
    @model = model.presence || determine_model(reasoning_model)
    @client = create_client
    # We pass raw streaming events (converted to hashes) to the handler.
    # The handler decides how to render/broadcast output to the UI.
    @stream_handler = wrap_stream_handler(stream_handler)
    @tools = []
    @tools.concat(determine_tools) if enable_tools
    @tools.concat(normalize_native_tools(native_tools))
    @tools = @tools.uniq { |tool| tool.to_json }.presence
    @log_completion = log_completion
    @store = store.nil? ? true : store
    @active_store = @store
    @previous_response_id = resolve_previous_response_id(previous_response_id)

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
  # - instructions: system/developer guidance (if omitted, derived from messages or base prompt).
  # - response_format/schema: supports structured output via JSON schema (text.format).
  # - store/previous_response_id: stateful context chaining (useful for chats).
  #
  # For stateful chat flows:
  # - Call once with store: true (default) and no previous_response_id.
  # - Reuse the same instance and it will set previous_response_id automatically
  #   based on the last response id, allowing you to send only new inputs.
  def complete(messages = nil, input: nil, instructions: nil, response_format: nil, schema: nil, temperature: 1, store: nil, previous_response_id: nil, include: nil, background: false, metadata: nil, max_output_tokens: nil, max_tool_calls: nil, parallel_tool_calls: nil, tool_choice: nil)
    with_openai_error_handling do
      check_cost_limits
      format_type = response_format_type(response_format)

      input_items = input.presence || build_input_from_messages(messages)
      raise OpenAiError, "Input is required for Responses API." if input_items.blank?

      instructions = build_instructions(messages, instructions)

      request_params = {
        model: @model,
        input: input_items,
        temperature: temperature,
        **(instructions.present? ? { instructions: instructions } : {}),
        **(@tools.present? ? { tools: @tools } : {}),
        **(include.present? ? { include: include } : {}),
        **(background ? { background: true } : {}),
        **(metadata.present? ? { metadata: metadata } : {}),
        **(max_output_tokens.present? ? { max_output_tokens: max_output_tokens } : {}),
        **(max_tool_calls.present? ? { max_tool_calls: max_tool_calls } : {}),
        **(parallel_tool_calls.present? ? { parallel_tool_calls: parallel_tool_calls } : {}),
        **(tool_choice.present? ? { tool_choice: tool_choice } : {}),
        **build_text_params(response_format)
      }

      state_params = build_state_params(store: store, previous_response_id: previous_response_id)
      @active_store = state_params.fetch(:store, @store)
      request_params.merge!(state_params) if state_params.present?

      # Set thinking for OpenRouter
      if @reasoning_model_flag && @base_uri.include?("openrouter.ai")
        request_params[:reasoning] = { effort: "high", exclude: false }
      end

      request_options = build_request_options
      request_options_param = request_options.present? ? { request_options: request_options } : {}

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

      Rails.logger.debug "Responses API response: #{response_hash}"

      set_last_response(response_hash, response)

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
      response_hash
    end
  end

  # Poll a background response until terminal status or timeout.
  # Returns the final response hash.
  def wait_for_response(response_id, timeout_seconds: 600, poll_interval_seconds: 2, include: nil)
    deadline = Time.current + timeout_seconds

    loop do
      response_hash = retrieve_response(response_id, include: include)
      status = response_hash["status"].to_s

      if status == "completed"
        log_completion(response_hash)
        return response_hash
      end

      return response_hash if %w[failed cancelled incomplete].include?(status)

      if Time.current >= deadline
        raise OpenAiError, "Background response timed out after #{timeout_seconds} seconds."
      end

      sleep(poll_interval_seconds)
    end
  end

  def cancel_response(response_id)
    with_openai_error_handling(unexpected_message: "Failed to cancel response") do
      raise OpenAiError, "response_id is required." if response_id.blank?

      request_options = build_request_options
      request_options_param = request_options.present? ? { request_options: request_options } : {}
      response = @client.responses.cancel(response_id, **request_options_param)
      normalize_response_hash(response)
    end
  end

  def output_text(response_hash = nil)
    target = response_hash || normalize_response_hash(@last_response)
    extract_output_text(target)
  end

  private

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
    nonreasoning_model = @user.setting.llm_model_name.presence || ENV.fetch("DEFAULT_MODEL")

    if reasoning_model_flag && reasoning_model
      reasoning_model
    elsif reasoning_model_flag && !reasoning_model
      Rails.logger.info "Reasoning model flag is set, but no reasoning model is configured. Falling back to default model: #{nonreasoning_model}"
      nonreasoning_model
    else
      nonreasoning_model
    end
  end

  def create_client
    # Future optimization: Reuse by adding client cache keyed by base_url + api_key, as each client has a connection pool of 99
    OpenAI::Client.new(
      api_key: @access_token,
      base_url: ensure_trailing_slash(@base_uri),
      max_retries: 2,
      timeout: 60
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
    headers = attribution_headers
    options[:extra_headers] = headers if headers.present?

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
    effective_store = store.nil? ? @store : store
    effective_previous = previous_response_id.presence || @previous_response_id || conversation_previous_response_id

    params = { store: effective_store }
    if effective_store && effective_previous.present?
      params[:previous_response_id] = effective_previous
    end
    params
  end

  # Prefer explicit instructions if provided.
  # Otherwise, use system messages from the input, or fall back to the
  # default system prompt constructed in initialize.
  def build_instructions(messages, explicit_instructions)
    return explicit_instructions if explicit_instructions.present?

    system_messages = Array(messages).select { |m| hash_value(m, :role).to_s == "system" }
    if system_messages.present?
      system_messages.map { |m| hash_value(m, :content).to_s }.join("\n\n")
    else
      @system_prompt
    end
  end

  # Convert Chat Completions-style messages into Responses input items.
  # We skip system messages here because instructions are provided separately.
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
      return {
        "type" => "function_call_output",
        "call_id" => tool_call_id,
        "output" => output
      }
    end

    items = []
    content = normalize_message_content(hash_value(message, :content))
    items << { "role" => role, "content" => content } if content.present?

    tool_calls = hash_value(message, :tool_calls)
    if role == "assistant" && tool_calls.present?
      items.concat(build_function_call_items(tool_calls))
    end

    items
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
      call_id = hash_value(tool_call, :id)
      name = hash_value(function, :name)
      next if call_id.blank? || name.blank?

      {
        "type" => "function_call",
        "call_id" => call_id,
        "name" => name,
        "arguments" => hash_value(function, :arguments) || ""
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
    log_completion(response_hash)
  end

  # Record the last response so callers can chain stateful requests.
  # When store is enabled, we treat the last response id as previous_response_id.
  def set_last_response(response_hash, response_obj)
    @last_response = response_obj
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
    if content.blank? && !response_contains_tool_calls?(response_hash)
      Rails.logger.warn "Empty response from LLM."
      raise OpenAiError, "Empty response from LLM."
    end
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
    match_json = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
    json_content = code_block_json.presence || match_json.presence || content.strip
    Rails.logger.info "Extracted JSON: #{json_content}"
    raise OpenAiError, "No valid JSON found in the LLM response." unless json_content.present?

    begin
      parsed_content = JSON.parse(json_content)
    rescue JSON::ParserError
      begin
        Rails.logger.info "Invalid JSON in LLM response, attempting to repair"
        repaired_content = JSON.repair(json_content)
        Rails.logger.info "Repaired JSON: #{repaired_content}"
        parsed_content = JSON.parse(repaired_content)
      rescue JSON::JSONRepairError => e
        raise OpenAiError, "Invalid JSON in LLM response, unable to repair: #{e.message}"
      rescue JSON::ParserError => e
        raise OpenAiError, "Invalid JSON in LLM response, unable to repair: #{e.message}"
      end
    end

    parsed_content
  end

  def validate_JSON(parsed_content, schema)
    schemer = JSONSchemer.schema(schema)
    unless schemer.valid?(parsed_content)
      errors = schemer.validate(parsed_content).to_a
      raise OpenAiError, "Please try again, or try a more intelligent LLM. Invalid JSON structure: #{errors.map { |e| e['error'] }.join(', ')}"
    end
  end

  def determine_tools
    allowed_tools = Tool.enabled_for_user(@user)

    if @conversation&.lesson_progress.present?
      allowed_tools = allowed_tools.where(access: :student)
    end

    if @conversation&.lesson_progress.blank? && @user.role_teacher?
      allowed_tools = allowed_tools.reject { |tool| tool.name == "View_Applets" }
    end

    allowed_tools.map { |tool| format_response_tool(tool) }
                 .reject { |tool| tool["name"] == "Generate_Image" && !@base_uri.include?("openrouter.ai") }
  end

  def normalize_native_tools(native_tools)
    Array(native_tools).filter_map do |tool|
      case tool
      when String, Symbol
        { "type" => tool.to_s }
      when Hash
        normalized = tool.deep_stringify_keys
        normalized["type"].present? ? normalized : nil
      else
        nil
      end
    end
  end

  def format_response_tool(tool)
    spec = tool.respond_to?(:specifications) ? tool.specifications : tool
    name = spec["name"] || spec[:name]
    {
      "type" => "function",
      "name" => name,
      "description" => spec["description"] || spec[:description],
      "parameters" => spec["parameters"] || spec[:parameters],
      "strict" => spec["strict_mode"] || spec[:strict_mode]
    }.compact
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

    Completion.create(
      conversation: @conversation,
      user: @user,
      model: response_hash["model"] || @model,
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

    conversation_previous_response_id
  end

  # Persist the latest response id to the conversation so the next call
  # can chain via previous_response_id without re-sending full history.
  def update_conversation_state
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

  def hash_value(hash, key)
    return nil unless hash.respond_to?(:[])
    hash[key] || hash[key.to_s]
  end

  def normalize_function_call_output(content)
    return "" if content.nil?
    return content if content.is_a?(String)

    normalized = normalize_message_content(content)
    return normalized if normalized.is_a?(Array)

    normalized.to_s
  end

  def conversation_previous_response_id
    return nil unless @conversation
    return nil unless @conversation.responses_state_matches?(provider: @base_uri, model: @model)

    @conversation.responses_previous_id
  end
end
