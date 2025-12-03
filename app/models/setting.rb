class Setting < ApplicationRecord
  belongs_to :user
  # user.settings is alias for user.setting

  # Settings is a JSONB column; so it is not necessary to perform a DB migration to change the settings fields
  # t.jsonb :settings, null: false, default: {}

  # Encrypt all settings in the DB
  encrypts :settings

  before_validation :ensure_llm_api_base_uri_trailing_slash

  # add a store_accessor for each settings key to add methods to read/write it
  # e.g. user.settings.pref1="123", user.settings.save!
  store_accessor :settings, :llm_model_name
  store_accessor :settings, :llm_api_access_token
  store_accessor :settings, :llm_api_base_uri
  store_accessor :settings, :reasoning_model_name
  store_accessor :settings, :notification_preferences

  # keys that should be inherited from the teacher's settings for students:
  INHERITED_SETTING_KEYS = %i[
    llm_model_name
    reasoning_model_name
    llm_api_access_token
    llm_api_base_uri
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

  # Provide default notification preferences if none are set
  def notification_preferences
    defaults = {
      "important" => { "email" => true, "in_app" => true },
      "student_progress" => { "email" => false, "in_app" => true }
    }
    # Deep merge defaults with stored value to ensure new keys appear
    defaults.deep_merge(super || {})
  end

  # Check if an LLM is configured
  def llm_configured?
    # Effective base URI (user setting or ENV) and normalize trailing slash
    base_uri = ensure_trailing_slash(llm_api_base_uri.presence || ENV["OPENAI_API_BASE_URL"])

    has_base = base_uri.present?
    has_model = llm_model_name.present? || ENV["DEFAULT_MODEL"].present?

    # ENV key is only usable if the chosen base_uri matches the ENV base URI
    env_base = ensure_trailing_slash(ENV["OPENAI_API_BASE_URL"])
    env_key_usable = ENV["OPENAI_API_KEY"].present? && env_base.present? && has_base && (env_base == base_uri)

    has_access_token =
      llm_api_access_token.present? ||
      (has_base && SupportedApi.selectable_for_teachers.exists?(api_base_uri: base_uri)) ||
      env_key_usable

    has_base && has_access_token && has_model
  end

  private

  def ensure_trailing_slash(url)
    return url if url.blank? || url.end_with?("/")
    "#{url}/"
  end

  def ensure_llm_api_base_uri_trailing_slash
    # Note: We are modifying the value directly using the store_accessor method
    # This ensures the change is saved to the JSONB column
    self.llm_api_base_uri = ensure_trailing_slash(llm_api_base_uri) if llm_api_base_uri.present?
  end
end
