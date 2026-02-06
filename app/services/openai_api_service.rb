class OpenaiApiService
  # Wrapper around official OpenAI Ruby SDK for LLM completions.
  require "json/repair"
  include OpenaiResponseHelper
  include OpenaiErrorHelper

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
    @base_uri = base_uri.presence || current_user.settings.llm_api_base_uri.presence || default_base_uri
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
    messages = Array(messages).dup

    # Inject system prompt to messages if it's not already included
    unless messages.any? { |message| [ message[:role], message["role"] ].compact.first == "system" }
      messages.unshift({ role: "system", content: @system_prompt })
    end

    # Inject prefilled assistant message unless OpenAI is being used
    if prefill && !@base_uri.include?("api.openai.com")
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

        # By default, OpenAI sets thinking budget to medium, and doesn't include the summary

        # Set thinking for OpenRouter
        **(@reasoning_model_flag && @base_uri.include?("openrouter.ai") ? {
          reasoning: {
            effort: "high",
            exclude: false
          }
        } : {}),

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
        log_completion(@finish_chunk&.dig("model") || @model)
        return
      end

      response = @client.chat.completions.create(**request_params, **request_options_param)
      response_hash = normalize_response_hash(response)

      Rails.logger.debug "API response: #{response_hash}"

      # Store the Completion record. Handle streaming and non-streaming cases.
      @usage = response_hash&.dig("usage")
      log_completion(response_hash&.dig("model") || @model)

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
      # Prefill is not supported by OpenAI platform.
      if !@base_uri.include?("api.openai.com") && prefill.present? && !normalized_content.start_with?(normalized_prefill)
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
      # Use the user's reasoning model
      reasoning_model
    elsif reasoning_model_flag && !reasoning_model
      Rails.logger.info "Reasoning model flag is set, but no reasoning model is configured. Falling back to default model: #{nonreasoning_model}"
      nonreasoning_model
    else
      # Use the user's regular model, or fall back to the default model
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

    # Set thinking for Google OpenAI-compatibility API
    if @reasoning_model_flag && @base_uri.include?("generativelanguage.googleapis.com")
      options[:extra_body] = {
        "google": {
          "thinking_config": {
            "thinking_budget": "3000",
            "include_thoughts": "False"
          }
        }
      }
    end

    options.presence
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
    # Try to rescue bad responses by removing things before and after the JSON
    match_json = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
    json_content = code_block_json.presence || match_json.presence || content.strip
    Rails.logger.info "Extracted JSON: #{json_content}"
    unless json_content.present?
      raise OpenAiError, "No valid JSON found in the LLM response."
    end

    # Parse the JSON
    begin
      # Rails.logger.debug "Parsing JSON: #{json_content}"
      parsed_content = JSON.parse(json_content)
    rescue JSON::ParserError => e
      # If invalid, try repairing the JSON
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
    # Start with tools enabled for the current user
    allowed_tools = Tool.enabled_for_user(@user)

    # If this is a lesson conversation, only provide student-level tools
    # This ensures teachers previewing lessons as students don't get curriculum tools
    if @conversation&.lesson_progress.present?
      allowed_tools = allowed_tools.where(access: :student)
    end

    if @conversation&.lesson_progress.blank? && @user.role_teacher?
      # In non-lesson chats, avoid sending both Manage_Applets and View_Applets to teachers.
      allowed_tools = allowed_tools.reject { |tool| tool.name == "View_Applets" }
    end

    # Format tools for LLM
    allowed_tools.map(&:for_llm)
                 # Reject image generation tool if not using OpenRouter
                 .reject { |tool| tool.dig("function", "name") == "Generate_Image" && !@base_uri.include?("openrouter.ai") }
  end

  def check_cost_limits
    daily_budget = @user.daily_budget
    max_chat_cost = AppSetting.settings&.max_chat_cost

    return unless daily_budget.present? || max_chat_cost.present?

    # 1. Check daily budget
    if daily_budget.present?
      daily_spend = Completion.where(user: @user).in_date_range(Date.current, Date.current).sum(:total_cost)
      if daily_spend >= daily_budget
        in_active_lesson = @conversation&.lesson_progress.present? && !@conversation.lesson_progress.completed?
        lesson_overage_limit = daily_budget * 1.25
        over_lesson_allowance = daily_spend >= lesson_overage_limit

        # Allow active lessons to continue up to a 25% overage, otherwise block.
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

    # 2. Check chat/lesson limit (runaway prevention)
    # This applies to both lessons and generic chats
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
    # Notify superusers
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

  def log_completion(model_name)
    return unless @log_completion

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
      total_cost: @usage&.dig("cost")&.to_f,
      cache_discount: @usage&.dig("cache_discount")&.to_f
    )
  end
end
