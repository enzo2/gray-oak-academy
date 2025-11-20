class EmbeddingService
  def self.get(text)
    return nil unless AppSetting.embeddings_configured?
    return nil if text.blank?

    new(text).fetch
  end

  def initialize(text)
    @text = text
    @model = AppSetting.settings.embedding_model
    @client = create_client
  end

  def fetch
    response = @client.embeddings(
      parameters: {
        model: @model,
        input: @text
      }
    )

    response.dig("data", 0, "embedding")
  rescue StandardError => e
    Rails.logger.error("Error generating embedding: #{e.message}")
    nil
  end

  private

  def create_client
    open_router = SupportedApi.find_by(api_base_uri: "https://openrouter.ai/api/v1/")
    token = open_router&.api_access_token

    OpenAI::Client.new(
      access_token: token,
      uri_base: "https://openrouter.ai/api/v1",
      log_errors: true
    )
  end
end
