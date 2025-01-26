class OpenaiApiService
  # Wrapper around ruby-openai gem
  # Base URI set in config/initializers/openai.rb

  require "faraday/retry"

  # To enable streaming, provide a stream_handler Proc that processes the streamed data as it arrives.
  # Each chunk delta will be passed to the Proc as a JSON object.
  # eg. { "role"=>"assistant", "content"=>"or not to be??" }

  # Provide the system prompt upon initializing the client, and it will be added to the conversation.
  # If no system prompt is provided, the default system prompt will be used.
  # However, if a system message is already present in the completion messages, that will be used instead.

  def initialize(model:, access_token: nil, stream_handler: nil, task_system_prompt: nil, enable_tools: false)
    @model = model.presence || default_model
    @access_token = access_token.presence || default_access_token
    @client = create_client
    @stream_handler = wrap_stream_handler(stream_handler)
    @base_system_prompt = Prompt.full_system_prompt
    if task_system_prompt
      @system_prompt = @base_system_prompt + " \n Now, focusing on your current role: " + task_system_prompt
    else
      @system_prompt = @base_system_prompt
    end
    @tools = Tool.all.map(&:for_llm) if enable_tools # Load tools if enabled
  end

  def complete(messages, extras: {}, schema: nil)
    # inject system prompt to messages if it's not already included
    unless messages.any? { |message| message[:role] == "system" }
      messages.unshift({ role: "system", content: @system_prompt })
    end

    # add tools to extras, if enabled
    extras[:tools] = @tools if @tools.present?

    response = @client.chat(
      parameters: {
        messages: messages,
        model: @model,
        temperature: 1,
        tools: extras.dig(:tools),
        response_format: extras.dig(:response_format),
        stream: @stream_handler,
        **(!ENV["OPENAI_API_BASE_URI"].include?("openrouter.ai") ? { stream_options: { include_usage: true } } : {})
      }
    )

    # If a stream handler was provided, stop here since the response was already handled
    # and will be blank. Handle logging token usage, cost, and refusal detection in the stream handler.
    return if @stream_handler

    # If OpenRouter was used, get cost afterwards and save to DB.
    if ENV["OPENAI_API_BASE_URI"].include?("openrouter.ai")
      # Delayed job to get generation stats from OpenRouter
      QueryOpenrouterGenerationStatsJob.set(wait: 5.seconds).perform_later(response.dig("id"))
    else # If not OpenRouter, use response stats directly
      usage = response.dig("usage")
      Completion.create(
        model: response.dig("model"),
        api_provider: ENV["OPENAI_API_BASE_URI"],
        # model_provider:
        prompt_tokens: usage.dig("prompt_tokens").to_i,
        completion_tokens: usage.dig("completion_tokens").to_i,
        total_tokens: usage.dig("total_tokens").to_i,
        prompt_audio_tokens: usage.dig("prompt_tokens_details", "audio_tokens").to_i,
        cached_tokens: usage.dig("prompt_tokens_details", "cached_tokens").to_i,
        reasoning_tokens: usage.dig("completion_tokens_details", "reasoning_tokens").to_i,
        completion_audio_tokens: usage.dig("completion_tokens_details", "audio_tokens").to_i,
      )
    end

    # If no stream handler was provided, process the response.
    check_for_refusal(response)
    content = response.dig("choices", 0, "message", "content")
    check_content(content)

    # If JSON requested, parse and validate the content.
    if extras.dig(:response_format, :type) == "json_object"
      parsed_content = parse_JSON(content)
      validate_JSON(parsed_content, schema) if schema.present?
      parsed_content
    else
      content
    end
  end

  private

  def default_model
    ENV.fetch("DEFAULT_MODEL") { raise "Model was neither provided nor set in ENV variable DEFAULT_MODEL." }
  end

  def default_access_token
    ENV.fetch("OPENAI_API_KEY") { raise "Access token was neither provided nor set in ENV variable OPENAI_API_KEY." }
  end

  def create_client
    retry_options = {
      max: 2,
      interval: 0.05,
      interval_randomness: 0.5,
      backoff_factor: 2
    }

    OpenAI::Client.new(access_token: @access_token) do |faraday|
      faraday.request :retry, retry_options
      faraday.response :logger, ::Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
        logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
      end
    end
  end

  def check_for_refusal(response)
    refusal = response.dig("choices", 0, "message", "refusal")
    if refusal.present?
      raise "Response refused with message: #{refusal}"
    end
  end

  def check_content(content)
    if content.blank?
      raise "Empty response from LLM."
    end
  end

  def parse_JSON(content)
    # Extract valid JSON from the response
    json_content = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
    unless json_content.present?
      raise "No valid JSON found in the LLM response."
    end

    # Parse the JSON
    begin
      # Rails.logger.debug "Parsing JSON: #{json_content}"
      parsed_content = JSON.parse(json_content)
    rescue JSON::ParserError => e
      raise "Failed to parse JSON from LLM response: #{e.message}"
    end

    parsed_content
  end

  def validate_JSON(parsed_content, schema)
    # Validate the parsed lessons against the schema
    schemer = JSONSchemer.schema(schema)
    unless schemer.valid?(parsed_content)
      errors = schemer.validate(parsed_content).to_a
      # Retry ?
      raise "Invalid lessons structure: #{errors.map { |e| e['error'] }.join(', ')}"
    end
  end

  def wrap_stream_handler(handler)
    # Return nil if no stream handler is provided, so streaming will be disabled
    return nil unless handler

    unless handler.is_a?(Proc)
      raise ArgumentError, "stream_handler must be a Proc"
    end

    Proc.new do |chunk|
      begin
        Rails.logger.debug chunk.inspect

        # Handle the final chunk with token usage
        if chunk["usage"]
          Rails.logger.debug("Streamed response complete: #{chunk["usage"]}")

          # If using OpenRouter, query the generation stats and saves to DB.
          if ENV["OPENAI_API_BASE_URI"].include?("openrouter.ai")
            QueryOpenrouterGenerationStatsJob.set(wait: 5.seconds).perform_later(chunk["id"])
          else # If not using OpenRouter, just save the usage from the response
            usage = chunk["usage"]
            Completion.create(
              model: @model,
              api_provider: ENV["OPENAI_API_BASE_URI"],
              # model_provider:
              prompt_tokens: usage.dig("prompt_tokens").to_i,
              completion_tokens: usage.dig("completion_tokens").to_i,
              total_tokens: usage.dig("total_tokens").to_i,
              prompt_audio_tokens: usage.dig("prompt_tokens_details", "audio_tokens").to_i,
              cached_tokens: usage.dig("prompt_tokens_details", "cached_tokens").to_i,
              reasoning_tokens: usage.dig("completion_tokens_details", "reasoning_tokens").to_i,
              completion_audio_tokens: usage.dig("completion_tokens_details", "audio_tokens").to_i,
              # latency:
              # generation_time:
            )
          end
        end

        choices = chunk.dig("choices")

        # Check for refusal
        refusal = choices.dig(0, "delta", "refusal")
        if refusal.present?
          raise "Response refused with message: #{refusal}"
        end

        # Call the actual handler with the LLM response
        handler.call(choices[0]) unless choices.empty?

      rescue StandardError => e
        # Handle any errors during processing
        puts "Error processing chunk: #{e.message}"
        # Optionally log or handle the error as needed
      end
    end
  end
end
