require "test_helper"

class BackgroundAgentConfigResolverTest < ActiveSupport::TestCase
  def setup
    @app_setting = app_settings(:one)
    @teacher = users(:admin)
    @teacher_setting = @teacher.setting
    @app_setting.update!(
      background_agent_supported_api_id: supported_apis(:openai).id,
      background_agent_model: "gpt-5.2",
      background_agent_prefer_user_codex: "0",
      background_agent_codex_model: nil
    )
    clear_oauth_credentials
  end

  test "preference disabled uses the shared fallback" do
    save_oauth_credentials(access_token: "teacher-codex-token")

    config = BackgroundAgentConfigResolver.resolve(user: @teacher)

    assert_equal SupportedApi::OPENAI_BASE_URI, config.base_uri
    assert_equal "openai-test-token", config.access_token
    assert_equal "gpt-5.2", config.model
    assert_equal "shared_supported_api", config.credential_source
    assert_equal({ stateful: true, async_background: true }, config.capabilities)
  end

  test "valid teacher OAuth uses Codex and an immutable resolved configuration" do
    @app_setting.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )
    save_oauth_credentials(access_token: "teacher-codex-token")

    config = BackgroundAgentConfigResolver.resolve(user: @teacher)

    assert_equal SupportedApi::OPENAI_CODEX_BASE_URI, config.base_uri
    assert_equal "teacher-codex-token", config.access_token
    assert_equal "gpt-5.4-codex", config.model
    assert_equal "user_codex_oauth", config.credential_source
    assert_equal({ stateful: false, async_background: false }, config.capabilities)
    assert_predicate config, :frozen?
    assert_predicate config.model, :frozen?
  end

  test "skip_user_codex bypasses the preferred Codex path and uses the shared fallback" do
    @app_setting.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )
    save_oauth_credentials(access_token: "teacher-codex-token")

    config = BackgroundAgentConfigResolver.resolve(user: @teacher, skip_user_codex: true)

    assert_equal SupportedApi::OPENAI_BASE_URI, config.base_uri
    assert_equal "openai-test-token", config.access_token
    assert_equal "gpt-5.2", config.model
    assert_equal "shared_supported_api", config.credential_source
  end

  test "missing teacher OAuth uses the shared fallback" do
    @app_setting.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )

    config = BackgroundAgentConfigResolver.resolve(user: @teacher)

    assert_equal SupportedApi::OPENAI_BASE_URI, config.base_uri
    assert_equal "shared_supported_api", config.credential_source
  end

  test "expired OAuth refreshes before selecting Codex" do
    @app_setting.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )
    save_oauth_credentials(
      access_token: "expired-token",
      refresh_token: "refresh-token",
      expires_at: 5.minutes.ago
    )
    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:refresh_access_token) do |refresh_token:|
      raise "unexpected refresh token" unless refresh_token == "refresh-token"

      { "access_token" => "fresh-token", "refresh_token" => "new-refresh-token", "expires_in" => 3600 }
    end

    config = OpenaiOauthService.stub(:new, -> { fake_oauth }) do
      BackgroundAgentConfigResolver.resolve(user: @teacher)
    end

    assert_equal SupportedApi::OPENAI_CODEX_BASE_URI, config.base_uri
    assert_equal "fresh-token", config.access_token
    assert_equal "fresh-token", @teacher_setting.reload.openai_oauth_access_token
  end

  test "invalid refresh credentials are cleared and use the shared fallback" do
    @app_setting.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )
    save_oauth_credentials(
      access_token: "expired-token",
      refresh_token: "invalid-refresh-token",
      expires_at: 5.minutes.ago
    )
    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:refresh_access_token) do |**|
      raise OpenaiOauthService::Error, "invalid_grant"
    end

    config = OpenaiOauthService.stub(:new, -> { fake_oauth }) do
      BackgroundAgentConfigResolver.resolve(user: @teacher)
    end

    assert_equal SupportedApi::OPENAI_BASE_URI, config.base_uri
    assert_equal "shared_supported_api", config.credential_source
    assert_not @teacher_setting.reload.openai_oauth_connected?
  end

  test "transient refresh failures preserve OAuth credentials and do not fall back" do
    @app_setting.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )
    save_oauth_credentials(
      access_token: "expired-token",
      refresh_token: "refresh-token",
      expires_at: 5.minutes.ago
    )
    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:refresh_access_token) do |**|
      raise OpenaiOauthService::Error, "temporarily unavailable"
    end

    assert_raises(BackgroundAgentConfigResolver::TransientOauthError) do
      OpenaiOauthService.stub(:new, -> { fake_oauth }) do
        BackgroundAgentConfigResolver.resolve(user: @teacher)
      end
    end

    assert_equal "refresh-token", @teacher_setting.reload.openai_oauth_refresh_token
    assert_equal "expired-token", @teacher_setting.openai_oauth_access_token
  end

  test "students cannot use inherited teacher OAuth credentials for background runs" do
    @app_setting.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )
    save_oauth_credentials(access_token: "teacher-codex-token")
    student = users(:student)

    assert_equal "teacher-codex-token", student.setting.openai_oauth_access_token
    assert_raises(OpenAiError) do
      BackgroundAgentConfigResolver.resolve(user: student)
    end
  end

  test "factory selects the Codex service once from the resolved route" do
    @app_setting.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )
    save_oauth_credentials(access_token: "teacher-codex-token")

    OpenAI::Client.stub(:new, Object.new) do
      service = OpenaiResponsesService.for_agent_run(user: @teacher, log_completion: false)

      assert_instance_of OpenaiCodexResponsesService, service
      assert_equal SupportedApi::OPENAI_CODEX_BASE_URI, service.base_uri
      assert_equal "user_codex_oauth", service.credential_source
      assert_not service.async_background_supported?
    end
  end

  private

  def save_oauth_credentials(access_token:, refresh_token: nil, expires_at: 1.hour.from_now)
    @teacher_setting.openai_oauth_access_token = access_token
    @teacher_setting.openai_oauth_refresh_token = refresh_token
    @teacher_setting.openai_oauth_expires_at = expires_at&.iso8601
    @teacher_setting.save!(validate: false)
  end

  def clear_oauth_credentials
    @teacher_setting.clear_openai_oauth_credentials!
  end
end
