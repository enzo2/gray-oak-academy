module OpenaiOauthTokenResolver
  private

  def resolve_openai_oauth_access_token
    return nil unless openai_provider_base_uri?(@base_uri)

    owner_setting = @user.setting.credential_owner_setting
    owner_setting.reload if owner_setting.persisted?

    return nil unless owner_setting.openai_oauth_access_token.present?
    return owner_setting.openai_oauth_access_token unless owner_setting.openai_oauth_expired?

    refresh_openai_oauth_access_token(owner_setting)
  end

  def refresh_openai_oauth_access_token(owner_setting)
    owner_setting.with_lock do
      owner_setting.reload

      if owner_setting.openai_oauth_access_token.present? && !owner_setting.openai_oauth_expired?
        return owner_setting.openai_oauth_access_token
      end

      refresh_token = owner_setting.openai_oauth_refresh_token.to_s
      if refresh_token.blank?
        Rails.logger.warn("#{self.class.name}: OpenAI OAuth refresh token is missing; clearing OAuth credentials.")
        clear_openai_oauth_credentials_safely(owner_setting)
        return nil
      end

      token_payload = OpenaiOauthService.new.refresh_access_token(refresh_token: refresh_token)
      owner_setting.save_openai_oauth_credentials!(token_payload: token_payload)
      owner_setting.openai_oauth_access_token
    end
  rescue OpenaiOauthService::Error => e
    if invalid_oauth_refresh_error?(e)
      Rails.logger.warn("#{self.class.name}: OpenAI OAuth refresh failed (#{e.message}); clearing OAuth credentials.")
      clear_openai_oauth_credentials_safely(owner_setting)
    else
      Rails.logger.warn("#{self.class.name}: OpenAI OAuth refresh failed (#{e.message}); keeping existing OAuth credentials.")
    end
    nil
  rescue StandardError => e
    Rails.logger.warn("#{self.class.name}: OpenAI OAuth refresh errored (#{e.message}); keeping existing OAuth credentials.")
    nil
  end

  def clear_openai_oauth_credentials_safely(setting)
    setting.clear_openai_oauth_credentials!
  rescue StandardError => e
    Rails.logger.error("#{self.class.name}: Failed to clear OpenAI OAuth credentials (#{e.message}).")
  end

  def openai_provider_base_uri?(base_uri)
    normalized = base_uri.to_s.strip
    normalized = "#{normalized}/" if normalized.present? && !normalized.end_with?("/")
    normalized == SupportedApi::OPENAI_CODEX_BASE_URI
  end

  def invalid_oauth_refresh_error?(error)
    message = error.message.to_s.downcase
    message.include?("invalid_grant") ||
      message.include?("invalid refresh token") ||
      message.include?("refresh token is invalid") ||
      message.include?("refresh token is expired") ||
      message.include?("missing refresh token")
  end
end
