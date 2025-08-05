class OpenaiApiService
  # Wrapper around ruby-openai gem
  require "json/repair"
  require "faraday/retry"

  # To enable streaming, provide a stream_handler Proc that processes the streamed data as it arrives, including tool calls and content.
  # Each chunk's choices[0] will be passed to the Proc as a JSON object.

  # System prompts are handled as follows:
  # If a custom system prompt is present in the completion messages array, it will be used as the system prompt.
  # If a task system prompt is provided, it will be added to the conversation, along with the base system prompt, teaching principles, and generative guidelines.
  # If neither a system prompt message, nor a task system prompt is provided, the default system prompt will be used (base system prompt + teaching principles).

  def initialize(current_user:, conversation: nil, access_token: nil, stream_handler: nil, task_system_prompt: nil, enable_tools: false, reasoning_model: false)
    # Don't initialize for orphaned students.
    raise OpenAiError, "Students can only use LLMs if they are adopted by a teacher." if current_user.role_student? && current_user.teacher.nil?

    @user = current_user
    @conversation = conversation
    @reasoning_model_flag = reasoning_model
    @model = determine_model(reasoning_model)
    @access_token = access_token.presence || default_access_token
    @base_uri = current_user.settings.llm_api_base_uri.presence || default_base_uri
    @client = create_client
    @stream_handler = wrap_stream_handler(stream_handler)
    @tools = Tool.all.map(&:for_llm) if enable_tools # Load tools if enabled

    # Jobs without a task system prompt will use the base system prompt only
    @system_prompt = Prompt.full_system_prompt(user: current_user)
    if task_system_prompt
      # Add the generative guidelines and the task system prompt to the base system prompt
      @system_prompt += "\n " +  Prompt.get_prompt(category: "generative_guidelines", user: current_user) + " \n Now, focusing on your current role: " + task_system_prompt
    end
  end

  def complete(messages, response_format: nil, schema: nil, prefill: nil)
    # inject system prompt to messages if it's not already included
    unless messages.any? { |message| message[:role] == "system" }
      messages.unshift({ role: "system", content: @system_prompt })
    end

    # inject prefilled assistant message unless OpenAI is being used
    if prefill && !@base_uri.include?("api.openai.com")
      messages << { role: "assistant", content: prefill }
    end

    begin
      response = @client.chat(
        parameters: {
          messages: messages,
          model: @model,
          temperature: 1,
          **(@tools.present? ? { tools: @tools } : {}),
          **(response_format.present? ? { response_format: response_format } : {}),
          stream: @stream_handler,

          # Request usage stats from OpenRouter
          **(@base_uri.include?("openrouter.ai") ? { usage: { include: true } } : {}),
          # Request usage stats when streaming
          **(@stream_handler && !@base_uri.include?("openrouter.ai") ? { stream_options: { include_usage: true } } : {}),

          # By default, OpenAI sets thinking budget to medium, and doesn't include the summary

          # Set thinking for OpenRouter
          **(@reasoning_model_flag && @base_uri.include?("openrouter.ai") ? {
            reasoning: {
              enabled: true,
              exclude: true
            }
          } : {}),

          # Set thinking for Google OpenAI-compatibility API
          **(@reasoning_model_flag && @base_uri.include?("generativelanguage.googleapis.com") ? {
            extra_body: {
              "google": {
                "thinking_config": {
                  "thinking_budget": "3000",
                  "include_thoughts": "False"
                }
              }
            }
          } : {})
        }
      )
      # Response will be empty if a stream handler was provided, as the response is handled while streaming.
      # If an error occurs, it will be handled by the rescue block and the following code will not be executed.

      Rails.logger.debug "API response: #{response}"

      # Store the Completion record. Handle streaming and non-streaming cases.
      @usage = @stream_handler ? @usage_chunk : response.dig("usage")
      Completion.create(
        conversation: @conversation,
        model: @stream_handler ? (@finish_chunk&.dig("model") || @model) : (response.dig("model") || @model),
        api_provider: @base_uri,
        # model_provider: @usage.dig["provider_name"],
        prompt_tokens: @usage.dig("prompt_tokens")&.to_i,
        prompt_audio_tokens: @usage.dig("prompt_tokens_details", "audio_tokens")&.to_i,
        cached_tokens: @usage.dig("prompt_tokens_details", "cached_tokens")&.to_i,
        completion_tokens: @usage.dig("completion_tokens")&.to_i,
        completion_audio_tokens: @usage.dig("completion_tokens_details", "audio_tokens")&.to_i,
        reasoning_tokens: @usage.dig("completion_tokens_details", "reasoning_tokens")&.to_i,
        total_tokens: @usage.dig("total_tokens")&.to_i,
        total_cost: @usage.dig("cost")&.to_f,
        cache_discount: @usage.dig("cache_discount")&.to_f
      )

      # If a stream handler was provided, stop here since the response was already handled
      # and will be blank. All processing should be done in the stream handler.
      return if @stream_handler

      # If no stream handler was provided, process the response.
      check_for_refusal(response)
      content = response.dig("choices", 0, "message", "content")

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

      check_content(content)

      # If JSON requested, parse and validate the content.
      if response_format.dig(:type) == "json_schema" || response_format.dig(:type) == "json_object"
        parsed_content = parse_JSON(content)
        validate_JSON(parsed_content, schema) if schema.present?
        Rails.logger.debug "Validated JSON content: #{parsed_content}"
        parsed_content
      else
        content
      end
    rescue Faraday::BadRequestError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "BadRequestError: #{e.message}: #{error_message}"
      raise OpenAiError, "The server rejected the request. Details: #{error_message}"
    rescue Faraday::TimeoutError => e
      Rails.logger.error "Faraday::TimeoutError #{e.message}"
      raise OpenAiError, "LLM did not respond in time. Ask your teacher to try a different model."
    rescue Faraday::ServerError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ServerError #{e.message}: #{error_message}"
      raise OpenAiError, "The server encountered an error. Details: #{error_message}"
    rescue Faraday::ClientError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ClientError #{e.message}"
      raise OpenAiError, "The client encountered an error. Details: #{error_message}"
    rescue Faraday::UnauthorizedError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::UnauthorizedError #{e.message}: #{error_message}"
      raise OpenAiError, "The access key was unauthorized. Ask teacher to check it."
    rescue Faraday::ResourceNotFound => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ResourceNotFound error #{e.message}: #{error_message}"
      raise OpenAiError, "The requested service was not found. Details: #{error_message}"
    rescue StandardError => e
      Rails.logger.error "StandardError #{e.inspect}"
      # Rails.logger.error "Trace: #{e.backtrace.join("\n")}"
      raise OpenAiError, "An unexpected error occurred: #{e.message}"
    end # end of begin/rescue/end block
  end

  def list_models
    response = @client.models.list
    response["data"].map { |model| model["id"] }
  rescue StandardError => e
    [ "Unable to list models: #{e.message}" ]
  end

  private

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

  def default_access_token
    @user.setting.llm_api_access_token.presence || ENV.fetch("OPENAI_API_KEY") { raise "Access token was neither provided nor set in ENV variable OPENAI_API_KEY." }
  end

  def default_base_uri
    ENV.fetch("OPENAI_API_BASE_URL") { raise "Base URL was neither entered in settings, nor set in ENV variable OPENAI_API_BASE_URL." }
  end

  def create_client
    retry_options = { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }
    OpenAI::Client.new(access_token: @access_token, uri_base: @base_uri) do |faraday|
      faraday.request :retry, retry_options
      faraday.response :logger, ::Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
        logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
      end
    end
  end

  def check_for_refusal(response)
    refusal = response.dig("choices", 0, "message", "refusal")
    if refusal.present?
      Rails.logger.warning "LLM refused to fulfill the request with message: #{refusal}"
      raise "Response refused with message: #{refusal}"
    end
  end

  def check_content(content)
    # Rails.logger.debug "Checking content: #{content}"
    if content.blank?
      Rails.logger.warning "Empty response from LLM."
      raise "Empty response from LLM."
    end
  end

  def parse_JSON(content)
    # Extract valid JSON from the response
    # Rails.logger.debug "Parsing JSON from LLM response: #{content}"
    json_content = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)  # Try to rescue lack of structured output by removing things before and after the JSON
    Rails.logger.info "Extracted JSON: #{json_content}"
    unless json_content.present?
      raise "No valid JSON found in the LLM response."
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
        Rails.logger.info "Repaired JSON: #{parsed_content}"
        parsed_content = JSON.parse(repaired_content)
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
      raise "Please try again, or try a more intelligent LLM. Invalid JSON structure: #{errors.map { |e| e['error'] }.join(', ')}"
    end
  end

  # This outer Proc will wrap the provided inner Proc.
  # The outer Proc will handle API-level concerns like checking for refusal, watching for the finish_reason, and logging the Completion.
  # The inner Proc provided should handle application-specic concerns like tool calls and extracting the completion content.
  def wrap_stream_handler(handler)
    # Return if no stream handler is provided, so streaming will be disabled
    return false unless handler

    unless handler.is_a?(Proc)
      raise ArgumentError, "stream_handler must be a Proc"
    end

    stream_finished = false
    @usage_chunk = {}

    Proc.new do |chunk|
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
          raise "Response refused with message: #{refusal}"
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

  def extract_faraday_error_message(exception)
    # Rails.logger.debug "#{exception.inspect}, #{exception.message}, #{exception.response[:body]}"
    response_body = exception.respond_to?(:response) ? exception.response[:body] : nil
    return "Unknown error" unless response_body
    Rails.logger.error "Error response body: #{response_body}"

    parsed = if response_body.is_a?(String)
      begin
        JSON.parse(response_body)
      rescue JSON::ParserError
        return "Failed to parse error response: #{response_body}"
      end
    else
      response_body # Already parsed
    end

    if parsed.is_a?(Array)
      parsed = parsed.first
    end

    Rails.logger.debug "Parsed error response: #{parsed.inspect}"

    if parsed.is_a?(Hash) && parsed["error"].is_a?(Hash)
      parsed["error"]["message"] || parsed["error"]["status"] || "Unknown error"
    else
      "Unknown error format: #{parsed.inspect}"
    end
  end
end

class OpenAiError < StandardError; end
