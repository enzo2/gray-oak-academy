# The model rows are auto-generated from the completion model.
# Used to store the context length and features, if the provider allows it to be queried. (OpenRouter)
class Llm < ApplicationRecord
  has_many :completions

  before_validation :ensure_api_provider_trailing_slash

  validates :model, presence: true
  validates :api_provider, presence: true
  validates :model, uniqueness: { scope: :api_provider, conditions: -> { with_archived } }
  validate :not_referenced_in_app_setting, on: :archive

  before_create :extract_model_provider_for_openrouter
  before_save :update_feature_flags_from_supported_parameters
  after_create_commit :update_metadata

  default_scope { where(archived_at: nil) }
  scope :with_archived, -> { unscope(where: :archived_at) }
  scope :archived, -> { with_archived.where.not(archived_at: nil) }

  def supports_bidirectional_speech?
    supports_audio_input && supports_audio_output
  end

  def archive
    self.archived_at = Time.current
    save(context: :archive)
  end

  def unarchive
    update!(archived_at: nil)
  end

  def archived?
    archived_at.present?
  end

  DEFAULT_API_BASE_URLS = [
    "https://openrouter.ai/api/v1/",
    "https://api.openai.com/v1/",
    SupportedApi::OPENAI_CODEX_BASE_URI
  ].freeze

  # Returns the full list of API base URIs, including the defaults, and any others that have been used
  def self.list_api_base_uris
    custom_uris = Llm.pluck(:api_provider).uniq
    supported_uris = SupportedApi.selectable_uris
    (DEFAULT_API_BASE_URLS + supported_uris + custom_uris).uniq
  end

  # Options for the LLM API Base URI combobox with a visual marker for supported providers.
  # Returns an array of [display, value] pairs, e.g. ["✓ https://openrouter.ai/api/v1/", "https://openrouter.ai/api/v1/"]
  def self.list_api_base_uri_options
    uris = list_api_base_uris
    supported = SupportedApi.selectable_uris
    uris.map do |uri|
      display = supported.include?(uri) ? "✓ #{uri}" : uri
      [ display, uri ]
    end
  end

  def self.list_models
    Llm.pluck(:model)
  end

  def supports_audio_input?
    supports_audio_input
  end

  def supports_image_input?
    supports_image_input
  end

  def supports_image_output?
    # Only support image models if the model can do image editing, since we use a 2-pass approach.
    supports_image_input && supports_image_output
  end

  def self.list_selectable_audio_models
    Llm.where(supports_audio_input: true, api_provider: SupportedApi.selectable_uris).order(:api_provider, :model)
  end

  # Return selectable image-capable models - only OpenRouter supported
  def self.list_selectable_image_models
    openrouter = SupportedApi.selectable_for_teachers.find_by(api_base_uri: "https://openrouter.ai/api/v1/")
    return [] unless openrouter
    Llm.where(supports_image_input: true, supports_image_output: true, api_provider: openrouter.api_base_uri).order(:model)
  end

  private

  # Sets a standard that API URIs will include the trailing slash
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

  # OpenRouter provides an endpoint for fetching model metadata.
  # Other providers are best-effort matched against models.dev.
  # If this initial check fails, recurring jobs retry daily (via recurring.yml).
  def update_metadata
    return unless metadata_stale?

    Rails.logger.debug "Updating metadata for LLM: #{self.inspect}"
    if api_provider.include?("openrouter.ai")
      UpdateOpenrouterModelMetadataJob.set(wait: 5.seconds).perform_later(self)
    else
      UpdateModelsDevModelMetadataJob.set(wait: 5.seconds).perform_later(self)
    end
  end

  def not_referenced_in_app_setting
    app_setting = AppSetting.first
    return unless app_setting

    if app_setting.image_llm_id.to_i == id
      errors.add(:archived_at, "cannot be set because this LLM is configured for image generation in app settings")
    end

    if app_setting.stt_model_id.to_i == id
      errors.add(:archived_at, "cannot be set because this LLM is configured for speech-to-text in app settings")
    end
  end
end
