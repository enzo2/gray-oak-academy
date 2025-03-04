class OpenRouterService
  # Wrapper around OpenRouter gem
  # Switched to ruby-openai gem, however still need this for running query_generation_stats, when OpenRouter is used.
  # This allows the actual cost to be obtained.

  require "faraday/retry"

  def initialize(user:, access_token: nil)
    @user = user
    @access_token = access_token.presence || default_access_token
    @base_uri = user.settings.llm_api_base_uri.presence || ENV.fetch("OPENAI_API_BASE_URI")
    if !@base_uri.include?("openrouter.ai")
      Rails.logger.warn "OpenRouterService is only compatible with OpenRouter API."
    end
    @client = create_client
  end

  # This should be called from a delayed job since it is not time-sensitive
  def query_generation_stats(id)
    @client.query_generation_stats(id)
  end

  private

  def default_access_token
    @user.setting.llm_api_access_token.presence || ENV.fetch("OPENAI_API_KEY") { raise "Access token was neither provided nor set in ENV variable OPENAI_API_KEY." }
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
end
