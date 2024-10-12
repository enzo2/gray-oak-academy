class OpenRouterService
  # Class for chat completions with OpenRouter.
  require "faraday/retry"

  def initialize(models: [], access_token: nil)
    @models = models.compact.empty? ? default_model : models
    @access_token = access_token || default_access_token
    @client = create_client
    @system_prompt = Prompt.category_base_system_prompt.first.prompt + Prompt.category_teaching_principles.first.prompt
  end

  def complete(messages, extras: {}, schema: nil)
    # Add system prompt to messages if it's not already given
    unless messages.any? { |message| message[:role] == "system" }
      messages.unshift({ role: "system", content: @system_prompt })
    end

    response = @client.complete(
      messages,
      model: @models,
      extras: extras
    )
    check_for_refusal(response)
    content = response.dig("choices", 0, "message", "content")
    check_content(content)
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
end
