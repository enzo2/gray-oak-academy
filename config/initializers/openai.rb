# Shared settings for the official OpenAI Ruby SDK clients.
module OpenaiClientDefaults
  DEFAULT_TIMEOUT_SECONDS = 240

  def self.timeout_seconds
    configured_timeout = ENV.fetch("OPENAI_CLIENT_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS.to_s).to_i
    configured_timeout.positive? ? configured_timeout : DEFAULT_TIMEOUT_SECONDS
  end
end
