class UserSettings::OpenaiOauthController < ApplicationController
  SESSION_DEVICE_AUTH_KEY = :openai_oauth_device_auth

  before_action :require_teacher
  before_action :require_oauth_configured

  def connect
    start_device_connect
  end

  def device
    @device_auth = session[SESSION_DEVICE_AUTH_KEY]&.with_indifferent_access
    if @device_auth.blank?
      redirect_to settings_path, alert: "OpenAI device authorization was not started. Please try again." and return
    end

    if device_auth_expired?(@device_auth)
      clear_device_auth_session!
      redirect_to settings_path, alert: "OpenAI device authorization expired. Please try again." and return
    end
  end

  def device_poll
    device_auth = session[SESSION_DEVICE_AUTH_KEY]&.with_indifferent_access
    if device_auth.blank?
      render json: { status: "error", message: "Device authorization was not started." }, status: :unprocessable_entity and return
    end

    if device_auth_expired?(device_auth)
      clear_device_auth_session!
      render json: { status: "expired", message: "OpenAI device authorization expired. Please try again." }, status: :unprocessable_entity and return
    end

    device_auth_result = oauth_service.poll_device_authorization(
      device_code: device_auth.fetch("device_code"),
      user_code: device_auth.fetch("user_code")
    )
    token_payload = oauth_service.exchange_device_authorization_code(
      authorization_code: device_auth_result.fetch(:authorization_code),
      code_verifier: device_auth_result.fetch(:code_verifier)
    )
    userinfo = oauth_service.extract_userinfo(token_payload: token_payload)

    owner_setting = current_user.settings.credential_owner_setting
    owner_setting.save_openai_oauth_credentials!(token_payload: token_payload, userinfo: userinfo)
    owner_setting.update!(llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI)
    clear_device_auth_session!

    Rails.logger.info(
      "OpenAI OAuth device auth success: host=#{request.host_with_port} sub=#{userinfo['sub'].inspect} " \
      "email=#{userinfo['email'].inspect}"
    )

    render json: { status: "connected", redirect_url: settings_path }
  rescue OpenaiOauthService::AuthorizationPendingError
    render json: { status: "pending" }
  rescue OpenaiOauthService::SlowDownError
    bump_device_auth_interval!
    render json: { status: "pending", interval_seconds: current_device_auth_interval }
  rescue OpenaiOauthService::ExpiredTokenError => e
    clear_device_auth_session!
    render json: { status: "expired", message: "OpenAI device authorization expired. Please try again." }, status: :unprocessable_entity
  rescue OpenaiOauthService::AccessDeniedError => e
    clear_device_auth_session!
    render json: { status: "denied", message: "OpenAI device authorization was denied." }, status: :unprocessable_entity
  rescue OpenaiOauthService::Error => e
    Rails.logger.error(
      "OpenAI OAuth device auth failure: host=#{request.host_with_port} message=#{e.message.inspect}"
    )
    render json: { status: "error", message: e.message }, status: :unprocessable_entity
  end

  def disconnect
    current_user.settings.credential_owner_setting.clear_openai_oauth_credentials!
    clear_device_auth_session!
    redirect_to settings_path, notice: "OpenAI account disconnected."
  end

  private

  def start_device_connect
    device_auth = oauth_service.start_device_authorization
    session[SESSION_DEVICE_AUTH_KEY] = {
      "device_code" => device_auth.fetch(:device_code),
      "user_code" => device_auth.fetch(:user_code),
      "verification_uri" => device_auth.fetch(:verification_uri),
      "expires_at" => (Time.current + device_auth.fetch(:expires_in).seconds).to_i,
      "interval_seconds" => [ device_auth.fetch(:interval), 1 ].max
    }

    Rails.logger.info(
      "OpenAI OAuth device auth start: host=#{request.host_with_port} verification_uri=#{device_auth[:verification_uri]} " \
      "user_code=#{device_auth[:user_code].inspect}"
    )

    redirect_to user_settings_openai_oauth_device_path
  rescue OpenaiOauthService::Error => e
    Rails.logger.error(
      "OpenAI OAuth device auth start failure: host=#{request.host_with_port} message=#{e.message.inspect}"
    )
    redirect_to settings_path, alert: "OpenAI device authorization failed: #{e.message}"
  end

  def oauth_service
    @oauth_service ||= OpenaiOauthService.new
  end

  def settings_path
    edit_user_registration_path(active_tab: :api)
  end

  def require_teacher
    return if current_user.role_teacher?

    redirect_to root_path, alert: "Only teachers can connect OpenAI OAuth."
  end

  def require_oauth_configured
    return if OpenaiOauthService.configured?

    redirect_to settings_path, alert: OpenaiOauthService.configuration_error
  end

  def clear_device_auth_session!
    session.delete(SESSION_DEVICE_AUTH_KEY)
  end

  def device_auth_expired?(device_auth)
    device_auth["expires_at"].to_i <= Time.current.to_i
  end

  def bump_device_auth_interval!
    device_auth = session[SESSION_DEVICE_AUTH_KEY]&.with_indifferent_access
    return unless device_auth.present?

    next_interval = [ device_auth["interval_seconds"].to_i + 5, 30 ].min
    device_auth["interval_seconds"] = next_interval
    session[SESSION_DEVICE_AUTH_KEY] = device_auth
  end

  def current_device_auth_interval
    session[SESSION_DEVICE_AUTH_KEY].to_h["interval_seconds"].to_i
  end
end
