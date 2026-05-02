class UpdateModelsDevModelMetadataJob < ApplicationJob
  queue_as :default

  MODELS_DEV_API_URL = "https://models.dev/api.json".freeze
  STALE_METADATA_WINDOW = 24.hours
  PROVIDER_KEYS_BY_HOST = {
    "api.openai.com" => "openai",
    "chatgpt.com" => "openai",
    "api.x.ai" => "xai"
  }.freeze

  def perform(llms = nil)
    data = fetch_models_dev_data
    return unless data.is_a?(Hash)

    if llms.nil?
      update_all_models(data)
      return
    end

    Array.wrap(llms).compact.each do |llm|
      update_metadata(llm, data)
    end
  end

  private

  def fetch_models_dev_data
    HttpJsonService.get(MODELS_DEV_API_URL)
  end

  def update_all_models(data)
    stale_non_openrouter_llms.find_each do |llm|
      update_metadata(llm, data)
    end
  end

  def stale_non_openrouter_llms
    Llm.where.not("api_provider LIKE ?", "%openrouter.ai%")
       .where("metadata_fetched_at IS NULL OR metadata_fetched_at < ?", STALE_METADATA_WINDOW.ago)
  end

  def update_metadata(llm, data)
    return if llm.api_provider.include?("openrouter.ai")

    model = model_metadata(llm, data)
    return unless model

    context_length = model.dig("limit", "context")
    return if context_length.blank?

    llm.update!(
      context_length: context_length,
      supports_audio_input: modality_supported?(model, direction: "input", modality: "audio"),
      supports_image_input: modality_supported?(model, direction: "input", modality: "image"),
      supports_audio_output: modality_supported?(model, direction: "output", modality: "audio"),
      supports_image_output: modality_supported?(model, direction: "output", modality: "image"),
      supports_tool_use: model["tool_call"],
      supports_structured_outputs: model["structured_output"],
      metadata_fetched_at: Time.current
    )
    Rails.logger.info("Updated models.dev metadata for #{llm.model}")
  rescue StandardError => e
    Rails.logger.error("Error updating models.dev metadata for #{llm.model}: #{e.message}")
  end

  def model_metadata(llm, data)
    provider = provider_metadata(llm, data)
    models = provider&.dig("models")
    return nil unless models.is_a?(Hash)

    model_ids(llm.model).each do |model_id|
      match = models[model_id] || models.values.find { |model| model["id"].to_s == model_id }
      return match if match
    end

    nil
  end

  def model_ids(model)
    raw = model.to_s
    ids = [ raw ]
    ids << raw.split("/", 2).last if raw.include?("/")
    ids << raw.sub(/-\d{4}-\d{2}-\d{2}\z/, "")
    ids.uniq.reject(&:blank?)
  end

  def provider_metadata(llm, data)
    host = uri_host(llm.api_provider)
    provider_key = PROVIDER_KEYS_BY_HOST[host]
    return data[provider_key] if provider_key.present? && data[provider_key].present?

    data.values.find do |provider|
      provider_api_matches?(llm.api_provider, provider["api"])
    end
  end

  def provider_api_matches?(configured_api, provider_api)
    configured = normalized_api_uri(configured_api)
    advertised = normalized_api_uri(provider_api)
    return false if configured.blank? || advertised.blank?

    configured == advertised ||
      configured.start_with?("#{advertised}/") ||
      advertised.start_with?("#{configured}/")
  end

  def normalized_api_uri(value)
    uri = URI.parse(value.to_s.strip)
    scheme = uri.scheme.to_s.downcase
    host = uri.host.to_s.downcase
    path = uri.path.to_s.sub(%r{/+\z}, "")
    return nil if scheme.blank? || host.blank?

    "#{scheme}://#{host}#{path}"
  rescue URI::InvalidURIError
    nil
  end

  def uri_host(value)
    URI.parse(value.to_s).host.to_s.downcase.presence
  rescue URI::InvalidURIError
    nil
  end

  def modality_supported?(model, direction:, modality:)
    Array(model.dig("modalities", direction)).include?(modality)
  end
end
