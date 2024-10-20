class OpenRouterService
  # Wrapper around OpenRouter gem

  require "faraday/retry"

  # To enable streaming, provide a Proc that processes the streamed data as it arrives.
  # Each chunk will be passed to the Proc as a JSON object.
  # The JSON object could be a data object or an error object.
  # eg. { "id"=>"gen-1729201039-HySih1bbH1k153vXHcNA", "provider"=>"Anthropic", "model"=>"anthropic/claude-3.5-sonnet:beta", "object"=>"chat.completion.chunk", "created"=>1729201039, "choices"=>[ { "index"=>0, "delta"=>{ "role"=>"assistant", "content"=>" have evolved?" }, "finish_reason"=>nil, "logprobs"=>nil } ] }

  def initialize(models: [], access_token: nil, stream_handler: nil, task_system_prompt: nil)
    @models = models.compact.empty? ? default_model : models
    @access_token = access_token || default_access_token
    @client = create_client
    @stream_handler = wrap_stream_handler(stream_handler)
    # Ensure the stream_handler is a Proc if provided
    @base_system_prompt = Prompt.category_base_system_prompt.first.prompt + " \n " + Prompt.category_teaching_principles.first.prompt
    if task_system_prompt
      @system_prompt = @base_system_prompt + " Specific task instructions: " + task_system_prompt
    else
      @system_prompt = @base_system_prompt
    end
  end

  def complete(messages, extras: {}, schema: nil)
    # inject system prompt to messages if it's not already included
    unless messages.any? { |message| message[:role] == "system" }
      messages.unshift({ role: "system", content: @system_prompt })
    end

    response = @client.complete(
      messages,
      model: @models,
      extras: extras,
      stream: @stream_handler
    )

    # If a stream handler was provided, stop here since the response was already handled.
    return if @stream_handler
    # If no stream handler was provided, process the response.
    check_for_refusal(response)
    content = response.dig("choices", 0, "message", "content")
    check_content(content)

    # Save usage info to DB.
    QueryOpenrouterGenerationStatsJob.set(wait: 5.seconds).perform_later(response.dig("id"))

    # If JSON requested, parse and validate the content.
    if extras.dig(:response_format, :type) == "json_object"
      parsed_content = parse_JSON(content)
      validate_JSON(parsed_content, schema) if schema.present?
      parsed_content
    else
      content
    end
  end

  def query_generation_stats(id)
    @client.query_generation_stats(id)
  end

  private

  def default_model
    [ ENV.fetch("DEFAULT_OPENROUTER_MODEL") { raise "Model was neither provided nor set in ENV variable DEFAULT_OPENROUTER_MODEL." } ]
  end

  def default_access_token
    ENV.fetch("OPENROUTER_ACCESS_TOKEN") { raise "Access token was neither provided nor set in ENV variable OPENROUTER_ACCESS_TOKEN." }
  end

  def create_client
    retry_options = {
      max: 2,
      interval: 0.05,
      interval_randomness: 0.5,
      backoff_factor: 2
    }

    OpenRouter::Client.new(access_token: @access_token) do |config|
      config.faraday do |f|
        f.request :retry, retry_options
        f.response :logger, ::Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
          logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
        end
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
    # Return nil if no stream handler is provided so streaming will be disabled
    return nil unless handler

    unless handler.is_a?(Proc)
      raise ArgumentError, "stream_handler must be a Proc"
    end

    Proc.new do |chunk|
      begin
        # Handle the JSON chunk, extracting the content
        content = chunk.dig("choices", 0, "delta", "content")
        raise "No valid content found in chunk" if content.nil?

        # Call the original handler with the extracted content
        handler.call(content) if content.present?

        # Handle the final chunk with token usage
        if chunk["usage"]
          log_token_usage(chunk["usage"])
        end

        # TODO: log cost
        #
      rescue StandardError => e
        # Handle any errors during processing
        puts "Error processing chunk: #{e.message}"
        # Optionally log or handle the error as needed
      end
    end
  end
end
