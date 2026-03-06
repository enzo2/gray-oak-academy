class Setting < ApplicationRecord
  belongs_to :user
  # user.settings is alias for user.setting

  # Settings is a JSONB column; so it is not necessary to perform a DB migration to change the settings fields
  # t.jsonb :settings, null: false, default: {}

  # Encrypt all settings in the DB
  encrypts :settings

  before_validation :ensure_llm_api_base_uri_trailing_slash
  validate :validate_model_availability

  # add a store_accessor for each settings key to add methods to read/write it
  # e.g. user.settings.pref1="123", user.settings.save!
  store_accessor :settings, :llm_model_name
  store_accessor :settings, :llm_api_access_token
  store_accessor :settings, :llm_api_base_uri
  store_accessor :settings, :reasoning_model_name
  store_accessor :settings, :notification_preferences
  store_accessor :settings, :openai_oauth_access_token
  store_accessor :settings, :openai_oauth_refresh_token
  store_accessor :settings, :openai_oauth_expires_at
  store_accessor :settings, :openai_oauth_sub
  store_accessor :settings, :openai_oauth_email

  # keys that should be inherited from the teacher's settings for students:
  INHERITED_SETTING_KEYS = %i[
    llm_model_name
    reasoning_model_name
    llm_api_access_token
    llm_api_base_uri
    openai_oauth_access_token
    openai_oauth_refresh_token
    openai_oauth_expires_at
    openai_oauth_sub
    openai_oauth_email
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
    defaults["agent_ops"] = { "email" => false, "in_app" => true } if user&.role_superuser?
    # Deep merge defaults with stored value to ensure new keys appear
    defaults.deep_merge(super || {})
  end

  # Effective LLM API base URI, with trailing slash normalization.
  def effective_llm_api_base_uri
    ensure_trailing_slash(llm_api_base_uri.presence || ENV["OPENAI_API_BASE_URL"])
  end

  # Parsed host from the effective LLM API base URI.
  def effective_llm_api_host
    uri = URI.parse(effective_llm_api_base_uri.to_s)
    uri.host&.downcase
  rescue URI::InvalidURIError
    nil
  end

  # Check if an LLM is configured
  def llm_configured?
    # Effective base URI (user setting or ENV) and normalize trailing slash
    base_uri = effective_llm_api_base_uri

    has_base = base_uri.present?
    has_model = llm_model_name.present? || ENV["DEFAULT_MODEL"].present?

    if openai_oauth_base_uri?(base_uri)
      return has_base && openai_oauth_usable_for_base_uri?(base_uri) && has_model
    end

    # ENV key is only usable if the chosen base_uri matches the ENV base URI
    env_base = ensure_trailing_slash(ENV["OPENAI_API_BASE_URL"])
    env_key_usable = ENV["OPENAI_API_KEY"].present? && env_base.present? && has_base && (env_base == base_uri)

    has_access_token =
      llm_api_access_token.present? ||
      (has_base && SupportedApi.selectable_for_teachers.exists?(api_base_uri: base_uri)) ||
      env_key_usable

    has_base && has_access_token && has_model
  end

  def credential_owner
    if user.role_student? && user.teacher.present?
      user.teacher
    else
      user
    end
  end

  def credential_owner_setting
    credential_owner.settings
  end

  def openai_oauth_expires_at_time
    value = openai_oauth_expires_at.to_s
    return nil if value.blank?

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end

  def openai_oauth_expired?(leeway_seconds: 60)
    expires_at = openai_oauth_expires_at_time
    return false if expires_at.blank?

    expires_at <= (Time.current + leeway_seconds.to_i.seconds)
  end

  def openai_oauth_connected?
    openai_oauth_access_token.present? || openai_oauth_refresh_token.present?
  end

  def openai_oauth_usable_for_base_uri?(base_uri)
    openai_oauth_base_uri?(base_uri) && openai_oauth_access_token.present?
  end

  def save_openai_oauth_credentials!(token_payload:, userinfo: nil)
    payload = token_payload.to_h.with_indifferent_access

    expires_at = if payload[:expires_at].present?
      Time.zone.parse(payload[:expires_at].to_s)
    elsif payload[:expires_in].present?
      Time.current + payload[:expires_in].to_i.seconds
    end

    attrs = {
      openai_oauth_access_token: payload[:access_token].presence || openai_oauth_access_token,
      openai_oauth_refresh_token: payload[:refresh_token].presence || openai_oauth_refresh_token,
      openai_oauth_expires_at: expires_at&.iso8601
    }

    userinfo_hash = userinfo.to_h.with_indifferent_access if userinfo
    if userinfo_hash.present?
      attrs[:openai_oauth_sub] = userinfo_hash[:sub].presence
      attrs[:openai_oauth_email] = userinfo_hash[:email].presence
    end

    attrs.each { |key, value| public_send("#{key}=", value) }
    save!(validate: false)
  end

  def clear_openai_oauth_credentials!
    self.openai_oauth_access_token = nil
    self.openai_oauth_refresh_token = nil
    self.openai_oauth_expires_at = nil
    self.openai_oauth_sub = nil
    self.openai_oauth_email = nil
    save!(validate: false)
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

  # Ensure teachers cannot select non-approved models using app/shared credentials.
  def validate_model_availability
    # Determine the effective base URI
    base_uri = effective_llm_api_base_uri
    return if base_uri.blank?

    # Personal credentials bypass shared-model restrictions.
    return if llm_api_access_token.present?
    return if openai_oauth_usable_for_base_uri?(base_uri)

    # Check if this is a supported API (shared token)
    is_shared_api = SupportedApi.selectable_for_teachers.exists?(api_base_uri: base_uri)
    env_base = ensure_trailing_slash(ENV["OPENAI_API_BASE_URL"])
    # Check if we are falling back to ENV credentials
    is_env_fallback = ENV["OPENAI_API_KEY"].present? && env_base.present? && (env_base == base_uri)

    # If this is a supported API or we are falling back to ENV credentials, validate the model availability
    return unless is_shared_api || is_env_fallback

    # Validate primary model
    if llm_model_name.present? && !Llm.exists?(model: llm_model_name, api_provider: base_uri)
      errors.add(:llm_model_name, "is not available or has been archived for this shared API. Add an override token to use new models.")
    end

    # Validate reasoning model
    if reasoning_model_name.present? && !Llm.exists?(model: reasoning_model_name, api_provider: base_uri)
      errors.add(:reasoning_model_name, "is not available or has been archived for this shared API. Add an override token to use new models.")
    end
  end

  def openai_oauth_base_uri?(base_uri)
    ensure_trailing_slash(base_uri.to_s) == SupportedApi::OPENAI_CODEX_BASE_URI
  end
end
