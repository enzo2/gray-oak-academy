class EmbeddingService
  include OpenaiResponseHelper

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
    response = @client.embeddings.create(
      model: @model,
      input: @text
    )

    payload = normalize_response_hash(response)
    payload.dig("data", 0, "embedding")
  rescue StandardError => e
    Rails.logger.error("Error generating embedding: #{e.message}")
    nil
  end

  private

  def create_client
    open_router = SupportedApi.find_by(api_base_uri: "https://openrouter.ai/api/v1/")
    token = open_router&.api_access_token

    OpenAI::Client.new(
      api_key: token,
      base_url: "https://openrouter.ai/api/v1/",
      max_retries: 2,
      timeout: 60
    )
  end
end
