class Setting < ApplicationRecord
  belongs_to :user
  # user.settings is alias for user.setting

  # Settings is a JSONB column; so it is not necessary to perform a DB migration to change the settings fields
  # t.jsonb :settings, null: false, default: {}

  # Encrypt all settings in the DB
  encrypts :settings

  before_validation :ensure_llm_api_base_uri_trailing_slash
  before_validation :ensure_speech_api_base_uri_trailing_slash

  # add a store_accessor for each settings key to add methods to read/write it
  # e.g. user.settings.pref1="123", user.settings.save!
  store_accessor :settings, :llm_model_name
  store_accessor :settings, :llm_api_access_token
  store_accessor :settings, :llm_api_base_uri
  store_accessor :settings, :speech_api_base_uri
  store_accessor :settings, :speech_api_access_token
  store_accessor :settings, :tts_model_name
  store_accessor :settings, :tts_voice_name
  store_accessor :settings, :tts_instructions
  store_accessor :settings, :stt_model_name
  store_accessor :settings, :reasoning_model_name

  # keys that should be inherited from the teacher's settings for students:
  INHERITED_SETTING_KEYS = %i[
    llm_model_name
    reasoning_model_name
    llm_api_access_token
    llm_api_base_uri
    speech_api_base_uri
    speech_api_access_token
    tts_model_name
    tts_voice_name
    tts_instructions
    stt_model_name
  ].freeze

  # Override the getter for each inherited setting key to return the teacher's setting, if the user is a student
  INHERITED_SETTING_KEYS.each do |key|
    define_method(key) do
      if user.role_student? && user.teacher
        user.teacher.settings.public_send(key)
      else
        super()
      end
    end
  end

  def speech_configured?
    speech_api_access_token.present?
    # All speech settings have defaults except the access token. URI defaults to OpenAI.
  end

  # Check if an LLM is configured
  def llm_configured?
    (llm_api_base_uri.present? || ENV["OPENAI_API_BASE_URL"].present?) &&
      (llm_api_access_token.present? || ENV["OPENAI_API_KEY"].present?) &&
      (llm_model_name.present? || ENV["DEFAULT_MODEL"].present?)
  end

  private

  def ensure_llm_api_base_uri_trailing_slash
    # Note: We are modifying the value directly using the store_accessor method
    # This ensures the change is saved to the JSONB column
    if llm_api_base_uri.present? && !llm_api_base_uri.end_with?("/")
      self.llm_api_base_uri = "#{llm_api_base_uri}/"
    end
  end

  def ensure_speech_api_base_uri_trailing_slash
    if speech_api_base_uri.present? && !speech_api_base_uri.end_with?("/")
      self.speech_api_base_uri = "#{speech_api_base_uri}/"
    end
  end
end
