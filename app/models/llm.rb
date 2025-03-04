# The model rows are auto-generated from the completion model.
# Used to store the context length and features, if the provider allows it to be queried. (OpenRouter)
class Llm < ApplicationRecord
  has_many :completions

  validates :model, presence: true
  validates :api_provider, presence: true
  validates :model, uniqueness: { scope: :api_provider }

  before_create :extract_model_provider_for_openrouter
  after_create :update_metadata

  private

  def extract_model_provider_for_openrouter
    if api_provider == "OpenRouter"
      self.model_provider = model.split("/").first
    end
  end

  def metadata_stale?
    metadata_fetched_at.nil? || metadata_fetched_at < 24.hours.ago
  end

  # OpenRouter provides an endpoint for fetching model metadata
  def update_metadata
    Rails.logger.debug "Updating metadata for LLM: #{self.inspect}"
    return unless api_provider == "OpenRouter" && metadata_stale?
    UpdateOpenrouterModelMetadataJob.perform_later(self) if metadata_stale?
  end
end
