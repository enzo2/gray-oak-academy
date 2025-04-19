# The model rows are auto-generated from the completion model.
# Used to store the context length and features, if the provider allows it to be queried. (OpenRouter)
class Llm < ApplicationRecord
  has_many :completions

  before_validation :ensure_api_provider_trailing_slash

  validates :model, presence: true
  validates :api_provider, presence: true
  validates :model, uniqueness: { scope: :api_provider }

  before_create :extract_model_provider_for_openrouter
  before_save :update_feature_flags_from_supported_parameters
  after_create_commit :update_metadata

  def supports_bidirectional_speech?
    supports_audio_input && supports_audio_output
  end

  def self.list_api_base_uris
    Llm.pluck(:api_provider).uniq
  end

  def self.list_models
    Llm.pluck(:model)
  end

  private

  def ensure_api_provider_trailing_slash
    if api_provider.present? && !api_provider.end_with?("/")
      self.api_provider = "#{api_provider}/"
    end
  end

  def extract_model_provider_for_openrouter
    if api_provider.include?("openrouter.ai")
      self.model_provider = model.split("/").first
    end
  end

  def update_feature_flags_from_supported_parameters
    return if supported_parameters.nil?

    self.supports_tool_use = supported_parameters.intersect?([ "tools", "tool_choice" ])
    self.supports_structured_outputs = supported_parameters.include?("structured_outputs")
  end

  def metadata_stale?
    metadata_fetched_at.nil? || metadata_fetched_at < 24.hours.ago
  end

  # OpenRouter provides an endpoint for fetching model metadata
  # If this initial check fails, will be retried as recurring job daily (via recurring.yml)
  def update_metadata
    return unless api_provider.include?("openrouter.ai") && metadata_stale?
    Rails.logger.debug "Updating metadata for LLM: #{self.inspect}"
    UpdateOpenrouterModelMetadataJob.set(wait: 5.seconds).perform_later(self) if metadata_stale?
  end
end
