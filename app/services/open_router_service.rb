class OpenRouterService
  # Class for chat completions with OpenRouter.
  require "faraday/retry"

  def initialize(model: nil)
    @model = model || default_model
    @client = create_client
  end

  def complete(messages, extras = {})
    response = @client.complete(
      messages,
      model: [ @model ],
      extras: extras
    )
    check_for_refusal(response)
    content = response.dig("choices", 0, "message", "content")
    check_content(content)
    if extras.dig(:extras, :response_format, :type) == "json_object"
      parse_JSON(content)
    else
      content
    end
  end

  private

  def default_model
    ENV.fetch("DEFAULT_OPENROUTER_MODEL") { raise "DEFAULT_OPENROUTER_MODEL is not set" }
  end

  def create_client
    retry_options = {
      max: 2,
      interval: 0.05,
      interval_randomness: 0.5,
      backoff_factor: 2
    }

    OpenRouter::Client.new(access_token: ENV.fetch("OPENROUTER_ACCESS_TOKEN")) do |config|
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
end
