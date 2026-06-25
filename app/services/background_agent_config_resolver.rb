class BackgroundAgentConfigResolver
  class TransientOauthError < OpenAiError; end
  # Raised when a per-teacher Codex run is rejected because the teacher's ChatGPT
  # subscription usage limit has been reached. Callers can recover by re-running
  # the background job with skip_user_codex: true, which routes to the shared
  # provider fallback. Carries the structured reset/plan details parsed from the
  # upstream body so callers can render teacher-facing text instead of the raw
  # message (see GenerationErrorPresenter).
  class CodexUsageLimitError < OpenAiError
    attr_reader :resets_at, :plan_type

    def initialize(message = nil, resets_at: nil, plan_type: nil)
      super(message)
      @resets_at = resets_at
      @plan_type = plan_type
    end
  end

  Configuration = Data.define(
    :provider,
    :base_uri,
    :access_token,
    :model,
    :credential_source,
    :capabilities
  )

  def self.resolve(user:, base_uri: nil, access_token: nil, model: nil, require_stateful: false, skip_user_codex: false)
    new(
      user: user,
      base_uri: base_uri,
      access_token: access_token,
      model: model,
      require_stateful: require_stateful,
      skip_user_codex: skip_user_codex
    ).resolve
  end

  def initialize(user:, base_uri:, access_token:, model:, require_stateful:, skip_user_codex: false)
    @user = user
    @base_uri_override = normalized_base_uri(base_uri).presence
    @access_token_override = access_token.to_s.presence
    @model_override = model.to_s.presence
    @require_stateful = require_stateful
    @skip_user_codex = skip_user_codex
  end

  def resolve
    unless @user&.role_teacher?
      raise OpenAiError, "Background agent runs require an initiating teacher."
    end

    @app_setting = AppSetting.settings
    unless @app_setting
      raise OpenAiError, "Background agent runs are not configured. Ask a superuser to set App Settings."
    end

    return resolve_affined_provider if @base_uri_override.present?

    resolve_preferred_user_codex || resolve_shared_fallback
  end

  private

  def resolve_preferred_user_codex
    return if @skip_user_codex
    return unless @app_setting.background_agent_prefer_user_codex?

    model = @model_override || @app_setting.background_agent_codex_model.to_s.presence
    if model.blank?
      raise OpenAiError, "Per-teacher Codex is enabled, but its model is not configured in App Settings."
    end

    token = resolve_user_codex_access_token
    return if token.blank?

    build_configuration(
      base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      access_token: token,
      model: model,
      credential_source: "user_codex_oauth"
    )
  end

  def resolve_shared_fallback
    model = @model_override || @app_setting.background_agent_model.to_s.presence
    if model.blank?
      raise OpenAiError, "Background agent runs model is not configured. Set it in App Settings."
    end

    provider = @app_setting.background_agent_supported_api
    unless provider
      raise OpenAiError, "Background agent runs provider is not configured. Select a supported provider with a shared token in App Settings."
    end

    token = @access_token_override || provider.api_access_token.to_s.presence
    unless token
      raise OpenAiError, "Background agent runs provider key is missing. Add a shared key for #{provider.api_base_uri} in LLM APIs."
    end

    build_configuration(
      base_uri: provider.api_base_uri,
      access_token: token,
      model: model,
      credential_source: @access_token_override.present? ? "explicit_override" : "shared_supported_api"
    )
  end

  def resolve_affined_provider
    if @base_uri_override == SupportedApi::OPENAI_CODEX_BASE_URI
      model = @model_override || @app_setting.background_agent_codex_model.to_s.presence
      raise OpenAiError, "The Codex model for this background run is unavailable." if model.blank?

      token = @access_token_override || resolve_user_codex_access_token
      unless token
        raise OpenAiError, "The initiating teacher's Codex OAuth credential is unavailable for this run."
      end

      return build_configuration(
        base_uri: @base_uri_override,
        access_token: token,
        model: model,
        credential_source: @access_token_override.present? ? "explicit_override" : "user_codex_oauth"
      )
    end

    provider = SupportedApi.find_responses_agent_selectable_by_base_uri(@base_uri_override)
    unless provider
      raise OpenAiError, "Background agent runs provider #{@base_uri_override} is unavailable."
    end

    model = @model_override || @app_setting.background_agent_model.to_s.presence
    raise OpenAiError, "The model for this background run is unavailable." if model.blank?

    token = @access_token_override || provider.api_access_token.to_s.presence
    unless token
      raise OpenAiError, "Background agent runs provider key is missing for #{@base_uri_override}."
    end

    build_configuration(
      base_uri: provider.api_base_uri,
      access_token: token,
      model: model,
      credential_source: @access_token_override.present? ? "explicit_override" : "shared_supported_api"
    )
  end

  def resolve_user_codex_access_token
    setting = @user.setting
    return if setting.blank?

    setting.reload if setting.persisted?
    if setting.openai_oauth_access_token.present? && !setting.openai_oauth_expired?
      return setting.openai_oauth_access_token
    end
    return if setting.openai_oauth_access_token.blank? && setting.openai_oauth_refresh_token.blank?

    refresh_user_codex_access_token(setting)
  end

  def refresh_user_codex_access_token(setting)
    setting.with_lock do
      setting.reload
      if setting.openai_oauth_access_token.present? && !setting.openai_oauth_expired?
        return setting.openai_oauth_access_token
      end

      refresh_token = setting.openai_oauth_refresh_token.to_s
      if refresh_token.blank?
        clear_oauth_credentials_safely(setting)
        return nil
      end

      token_payload = OpenaiOauthService.new.refresh_access_token(refresh_token: refresh_token)
      setting.save_openai_oauth_credentials!(token_payload: token_payload)
      setting.openai_oauth_access_token.to_s.presence
    end
  rescue OpenaiOauthService::Error => e
    if OpenaiOauthService.invalid_refresh_error?(e)
      Rails.logger.warn("BackgroundAgentConfigResolver: invalid OpenAI OAuth refresh credential; clearing it.")
      clear_oauth_credentials_safely(setting)
      nil
    else
      Rails.logger.warn("BackgroundAgentConfigResolver: transient OpenAI OAuth refresh failure; preserving credentials.")
      raise TransientOauthError, "The initiating teacher's Codex login could not be refreshed. Please retry the background run."
    end
  rescue TransientOauthError
    raise
  rescue StandardError => e
    Rails.logger.warn("BackgroundAgentConfigResolver: OpenAI OAuth refresh errored (#{e.class}); preserving credentials.")
    raise TransientOauthError, "The initiating teacher's Codex login could not be refreshed. Please retry the background run."
  end

  def clear_oauth_credentials_safely(setting)
    setting.clear_openai_oauth_credentials!
  rescue StandardError => e
    Rails.logger.error("BackgroundAgentConfigResolver: failed to clear invalid OpenAI OAuth credentials (#{e.class}).")
  end

  def build_configuration(base_uri:, access_token:, model:, credential_source:)
    base_uri = normalized_base_uri(base_uri)
    stateful = OpenaiResponsesService.stateful_supported_base_uri?(base_uri)
    if @require_stateful && !stateful
      raise OpenAiError,
            "Background agent runs provider #{base_uri} does not support required stateful Responses behavior. Select a stateful provider in App Settings."
    end

    Configuration.new(
      provider: immutable_string(OpenaiResponsesService.base_uri_host(base_uri)),
      base_uri: immutable_string(base_uri),
      access_token: immutable_string(access_token),
      model: immutable_string(model),
      credential_source: immutable_string(credential_source),
      capabilities: {
        stateful: stateful,
        async_background: OpenaiResponsesService.async_background_supported_base_uri?(base_uri)
      }.freeze
    )
  end

  def normalized_base_uri(base_uri)
    SupportedApi.normalize_base_uri(base_uri)
  end

  def immutable_string(value)
    value.to_s.dup.freeze
  end
end
