class AppSetting < ApplicationRecord
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
                 :token_override

  validates :singleton, inclusion: { in: [ true, false ] }

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

  # TTS/Speech considered configured if app-wide AppSetting is present and has a provider + token.
  def self.speech_configured?
    app_setting = self.first
    return false unless app_setting && app_setting.provider_base_uri.present?
    if app_setting.effective_token.present?
      true
    else
      false
    end
  end
end
