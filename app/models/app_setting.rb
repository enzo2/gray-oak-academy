class AppSetting < ApplicationRecord
  MASKED_SECRET_VALUE = "__STORED_SECRET__".freeze
  MAX_BACKGROUND_AGENT_TOOL_TURNS = 50
  LEGACY_BACKGROUND_AGENT_SETTING_KEYS = {
    "background_agent_supported_api_id" => "openai_agent_supported_api_id",
    "background_agent_model" => "openai_agent_model",
    "background_agent_max_tool_turns" => "openai_agent_max_tool_turns"
  }.freeze

  # Singleton app-wide settings stored in a JSONB `settings` column
  encrypts :settings

  # Expose common keys as accessors
  store_accessor :settings,
                 :provider_supported_api_id,
                 :stt_method,
                 :stt_model,
                 :stt_model_id,
                 :tts_model,
                 :tts_voice,
                 :tts_instructions,
                 :token_override,
                 :image_llm_id,
                 :embedding_model,
                 :image_generation_two_pass,
                 :user_daily_budget,
                 :max_chat_cost,
                 :background_agent_supported_api_id,
                 :background_agent_model,
                 :background_agent_max_tool_turns,
                 :exa_api_key,
                 :exa_research_model,
                 :course_outline_research_stub_enabled

  # Custom accessor to handle boolean casting and default value
  def image_generation_two_pass
    val = super
    return false if val.nil?
    ActiveModel::Type::Boolean.new.cast(val)
  end

  def user_daily_budget
    val = super
    return nil unless val.present?
    val.to_d
  end

  def max_chat_cost
    val = super
    return nil unless val.present?
    val.to_d
  end

  def exa_research_model
    super.presence || ExaApiService::DEFAULT_RESEARCH_MODEL
  end

  def course_outline_research_stub_enabled
    val = super
    return false if val.nil?
    ActiveModel::Type::Boolean.new.cast(val)
  end

  def course_outline_research_stub_enabled?
    Rails.env.development? && course_outline_research_stub_enabled
  end

  validates :singleton, inclusion: { in: [ true, false ] }
  before_validation :migrate_legacy_background_agent_settings
  before_validation :normalize_secret_fields
  validate :llms_not_archived, on: :update
  validate :embedding_model_validity, on: :update, if: :embedding_model_changed_in_settings?

  after_save :clear_embeddings_if_model_changed

  # Convenience accessor to always return the single app setting
  def self.settings
    first
  end

  # Return the associated SupportedApi record for the configured provider, if any
  def provider_supported_api
    return nil unless provider_supported_api_id.present?
    SupportedApi.find_by(id: provider_supported_api_id.to_i)
  end

  # Returns the effective API token to use: the SupportedApi token also used for chat, or an override token
  def effective_token
    token_override.presence || provider_supported_api&.api_access_token
  end

  # Returns provider base URI if configured
  def provider_base_uri
    provider_supported_api&.api_base_uri
  end

  # Image generation configuration
  def image_llm
    return nil unless image_llm_id.present?
    Llm.find_by(id: image_llm_id.to_i)
  end

  def image_effective_token
    return nil unless image_llm.present?
    provider = SupportedApi.selectable_for_teachers.find_by(api_base_uri: image_llm.api_provider)
    provider&.api_access_token
  end

  # Checks whether Speech API (OpenAI-compatible) is configured for TTS/STT
  def self.speech_configured?
    app_setting = self.first
    app_setting&.provider_base_uri.present? && app_setting&.effective_token.present?
  end

  def self.tts_configured?
    # Currently, Speech API is the only way to provide TTS.
    self.speech_configured?
  end

  # STT can be done via Speech API, or audio LLMs. Webmaster must choose.
  def self.stt_configured?
    app_setting = self.first
    return false unless app_setting

    case app_setting.stt_method
    when "speech" # Using Speech API for STT
      app_setting.provider_base_uri.present? &&
      app_setting.effective_token.present? &&
      app_setting.stt_model.present?
    when "chat" # Using LLM for STT
      app_setting.stt_model_id.present?
    else
      false
    end
  end

  def self.image_generation_configured?
    app_setting = self.first
    app_setting&.image_llm.present? &&
    app_setting.image_llm.supports_image_output? &&
    app_setting.image_effective_token.present?
  end

  def self.embeddings_configured?
    app_setting = self.first
    return false unless app_setting&.embedding_model.present?

    open_router = SupportedApi.find_by(api_base_uri: "https://openrouter.ai/api/v1/")
    open_router&.api_access_token.present?
  end

  def exa_enabled?
    exa_api_key.present? || ENV["EXA_API_KEY"].present?
  end

  def self.exa_enabled?
    settings&.exa_enabled? || ENV["EXA_API_KEY"].present? || false
  end

  # Legacy OpenAI shared API accessor used by older call sites.
  def openai_supported_api
    SupportedApi.openai_supported
  end

  def background_agent_supported_api
    if background_agent_supported_api_id.present?
      selected_api = SupportedApi.find_responses_agent_selectable_by_id(background_agent_supported_api_id)
      return selected_api if selected_api.present?
    end

    SupportedApi.openai_selectable
  end

  def background_agent_supported_api_id
    background_agent_setting_value("background_agent_supported_api_id")
  end

  def background_agent_model
    background_agent_setting_value("background_agent_model")
  end

  def background_agent_supported_apis
    SupportedApi.responses_agent_selectable
  end

  def background_agent_access_token
    background_agent_supported_api&.api_access_token
  end

  def background_agent_base_uri
    background_agent_supported_api&.api_base_uri
  end

  def background_agent_llm
    return nil if background_agent_base_uri.blank? || background_agent_model.blank?

    Llm.find_by(
      api_provider: SupportedApi.normalize_base_uri(background_agent_base_uri),
      model: background_agent_model
    )
  end

  def background_agent_context_length
    background_agent_llm&.context_length
  end

  def background_agent_context_metadata_missing?
    background_agent_model.present? &&
      background_agent_base_uri == SupportedApi::OPENROUTER_BASE_URI &&
      background_agent_context_length.blank?
  end

  def background_agent_enabled?
    background_agent_model.present? && background_agent_access_token.present?
  end

  def self.background_agent_enabled?
    settings&.background_agent_enabled? || false
  end

  def background_agent_max_tool_turns
    coerce_tool_turn_limit(background_agent_setting_value("background_agent_max_tool_turns"))
  end

  def self.background_agent_max_tool_turns
    settings&.background_agent_max_tool_turns
  end

  def self.course_outline_research_stub_enabled?
    return false unless Rails.env.development?

    settings&.course_outline_research_stub_enabled? || false
  end

  # Fetch and cache OpenRouter embedding models
  def self.fetch_openrouter_embedding_models
    Rails.cache.fetch("openrouter_embedding_models", expires_in: 1.hour) do
      url = "https://openrouter.ai/api/v1/embeddings/models"
      Rails.logger.debug("Fetching embedding models from #{url}")
      data = HttpJsonService.get(url)
      if data && data["data"]
        data["data"].map { |m| m["id"] }
      else
        []
      end
    end
  end

  def self.fetch_openrouter_tts_models
    fetch_openrouter_speech_model_data(kind: :tts).map { |model| model["id"] }.compact.sort
  end

  def self.fetch_openrouter_stt_models
    fetch_openrouter_speech_model_data(kind: :stt).map { |model| model["id"] }.compact.sort
  end

  def self.fetch_openrouter_tts_voices(model:)
    return [] if model.blank?

    model_data = fetch_openrouter_speech_model_data(kind: :tts).find { |entry| entry["id"] == model }
    Array(model_data&.dig("supported_voices")).compact.sort
  end

  def self.fetch_openrouter_speech_model_data(kind:)
    modality = case kind.to_s
    when "tts"
      "speech"
    when "stt"
      "transcription"
    else
      return []
    end

    # skip_nil ensures a transient fetch failure (HttpJsonService.get returns
    # nil on any error) is NOT cached, so the next request retries instead of
    # serving an empty list for up to an hour.
    Array(
      Rails.cache.fetch("openrouter_#{kind}_model_data", expires_in: 1.hour, skip_nil: true) do
        url = "#{SupportedApi::OPENROUTER_BASE_URI}models?output_modalities=#{modality}"
        Rails.logger.debug("Fetching OpenRouter #{kind} models from #{url}")
        data = HttpJsonService.get(url)
        data["data"] if data && data["data"].is_a?(Array)
      end
    )
  end

  private

  def background_agent_setting_value(key)
    value = settings.to_h[key]
    return value if value.present?

    legacy_key = LEGACY_BACKGROUND_AGENT_SETTING_KEYS.fetch(key)
    settings.to_h[legacy_key]
  end

  def migrate_legacy_background_agent_settings
    payload = settings
    return unless payload.is_a?(Hash)

    changed = false
    LEGACY_BACKGROUND_AGENT_SETTING_KEYS.each do |new_key, legacy_key|
      next unless payload.key?(legacy_key)

      legacy_value = payload.delete(legacy_key)
      payload[new_key] = legacy_value if payload[new_key].blank? && legacy_value.present?
      changed = true
    end
    settings_will_change! if changed
  end

  def normalize_secret_fields
    self.token_override = token_override.to_s.strip.presence
    self.exa_api_key = exa_api_key.to_s.strip.presence
  end

  def coerce_tool_turn_limit(value)
    parsed = Integer(value, exception: false)
    return nil unless parsed&.positive?

    [ parsed, MAX_BACKGROUND_AGENT_TOOL_TURNS ].min
  end

  def llms_not_archived
    if image_llm_id.present?
      llm = Llm.with_archived.find_by(id: image_llm_id.to_i)
      if llm&.archived?
        errors.add(:image_llm_id, "cannot be an archived model")
      end
    end

    if stt_model_id.present?
      llm = Llm.with_archived.find_by(id: stt_model_id.to_i)
      if llm&.archived?
        errors.add(:stt_model_id, "cannot be an archived model")
      end
    end
  end

  def embedding_model_validity
    return unless embedding_model.present?

    # 1. Check for OpenRouter token
    open_router = SupportedApi.find_by(api_base_uri: "https://openrouter.ai/api/v1/")
    unless open_router&.api_access_token.present?
      errors.add(:embedding_model, "requires a key for OpenRouter to be configured in LLM API settings")
      return
    end

    # 2. Check against available models
    available_models = AppSetting.fetch_openrouter_embedding_models
    unless available_models.include?(embedding_model)
      errors.add(:embedding_model, "must be a valid OpenRouter embedding model")
    end
  end

  def embedding_model_changed_in_settings?
    settings_change = changes_to_save["settings"]
    return false unless settings_change.present?

    previous_settings, current_settings = settings_change
    previous_embedding_model = previous_settings.to_h.with_indifferent_access[:embedding_model]
    current_embedding_model = current_settings.to_h.with_indifferent_access[:embedding_model]

    previous_embedding_model != current_embedding_model
  end

  def clear_embeddings_if_model_changed
    return unless saved_change_to_settings?

    # Check if embedding_model actually changed in the JSON settings
    previous_settings = saved_changes["settings"]&.first || {}
    current_settings = saved_changes["settings"]&.last || {}
    # Rails.logger.debug "Previous settings: #{previous_settings.inspect}"
    # Rails.logger.debug "Current settings: #{current_settings.inspect}"

    if previous_settings["embedding_model"] != current_settings["embedding_model"]
      Rails.logger.info("Embedding model changed from #{previous_settings['embedding_model']} to #{current_settings['embedding_model']}. Clearing all memory embeddings.")
      Memory.update_all(embedding: nil)
      BackfillMemoryEmbeddingsJob.perform_later
    end
  end
end
