module BackgroundAgentJob
  extend ActiveSupport::Concern

  OAUTH_RETRY_ATTEMPTS = 3

  included do
    const_set(:OAUTH_RETRY_ATTEMPTS, BackgroundAgentJob::OAUTH_RETRY_ATTEMPTS) unless const_defined?(:OAUTH_RETRY_ATTEMPTS, false)

    retry_on(
      BackgroundAgentConfigResolver::TransientOauthError,
      wait: :polynomially_longer,
      attempts: BackgroundAgentJob::OAUTH_RETRY_ATTEMPTS
    )
  end

  private

  def oauth_retries_exhausted?
    executions >= BackgroundAgentJob::OAUTH_RETRY_ATTEMPTS
  end

  # CodexUsageLimitError is only ever raised by the per-teacher Codex provider, so
  # receiving it already proves this run used Codex. Fall back only when a shared
  # provider is configured to take over; skip_user_codex guards the re-run against
  # an infinite Codex -> shared loop.
  def codex_fallback_available?(skip_user_codex:)
    return false if skip_user_codex

    AppSetting.background_agent_enabled?
  end
end
