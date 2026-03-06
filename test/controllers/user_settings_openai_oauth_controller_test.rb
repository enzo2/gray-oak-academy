require "test_helper"

class UserSettingsOpenaiOauthControllerTest < ActionDispatch::IntegrationTest
  def setup
    @teacher = users(:admin)
    sign_in(@teacher)
  end

  test "disconnect clears stored OAuth credentials" do
    @teacher.setting.update!(
      openai_oauth_access_token: "oauth_access_old",
      openai_oauth_refresh_token: "oauth_refresh_old",
      openai_oauth_expires_at: 1.hour.from_now.iso8601,
      openai_oauth_sub: "user_old",
      openai_oauth_email: "old@example.com"
    )

    delete user_settings_openai_oauth_disconnect_path

    assert_redirected_to edit_user_registration_path(active_tab: :api)
    assert_equal "OpenAI account disconnected.", flash[:notice]

    setting = @teacher.reload.setting
    assert_nil setting.openai_oauth_access_token
    assert_nil setting.openai_oauth_refresh_token
    assert_nil setting.openai_oauth_expires_at
    assert_nil setting.openai_oauth_sub
    assert_nil setting.openai_oauth_email
  end

  test "connect uses device auth flow for built-in public client on localhost" do
    previous_host = host
    host! "localhost:3000"
    sign_in(@teacher)

    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:start_device_authorization) do
      {
        device_code: "device-code-123",
        user_code: "ABCD-EFGH",
        verification_uri: "https://auth.openai.com/codex/device",
        expires_in: 900,
        interval: 5
      }
    end

    with_default_openai_oauth_env do
      OpenaiOauthService.stub(:new, -> { fake_oauth }) do
        get user_settings_openai_oauth_connect_path
      end
    end

    assert_redirected_to user_settings_openai_oauth_device_path

    get user_settings_openai_oauth_device_path
    assert_response :success
    assert_includes response.body, "ABCD-EFGH"
    assert_includes response.body, "https://auth.openai.com/codex/device"
  ensure
    host! previous_host if previous_host.present?
  end

  test "connect uses device auth flow for built-in public client on non-localhost host" do
    previous_host = host
    host! "academy.example.com"
    sign_in(@teacher)

    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:start_device_authorization) do
      {
        device_code: "device-code-123",
        user_code: "ABCD-EFGH",
        verification_uri: "https://auth.openai.com/codex/device",
        expires_in: 900,
        interval: 5
      }
    end

    with_default_openai_oauth_env do
      OpenaiOauthService.stub(:new, -> { fake_oauth }) do
        get user_settings_openai_oauth_connect_path
      end
    end

    assert_redirected_to user_settings_openai_oauth_device_path
  ensure
    host! previous_host if previous_host.present?
  end

  test "device_poll stores OAuth credentials without calling remote userinfo" do
    header = Base64.urlsafe_encode64({ alg: "none" }.to_json, padding: false)
    payload = Base64.urlsafe_encode64({ sub: "user_123", email: "teacher@example.com" }.to_json, padding: false)
    id_token = "#{header}.#{payload}.signature"
    real_oauth_service = OpenaiOauthService.new

    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:start_device_authorization) do
      {
        device_code: "device-code-123",
        user_code: "ABCD-EFGH",
        verification_uri: "https://auth.openai.com/codex/device",
        expires_in: 900,
        interval: 5
      }
    end
    fake_oauth.define_singleton_method(:poll_device_authorization) do |device_code:, user_code:|
      {
        authorization_code: "auth-code-123",
        code_verifier: "verifier-123"
      }
    end
    fake_oauth.define_singleton_method(:exchange_device_authorization_code) do |authorization_code:, code_verifier:|
      {
        "access_token" => "oauth-access-new",
        "refresh_token" => "oauth-refresh-new",
        "expires_in" => 3600,
        "id_token" => id_token
      }
    end
    fake_oauth.define_singleton_method(:extract_userinfo) do |token_payload:|
      real_oauth_service.extract_userinfo(token_payload: token_payload)
    end

    OpenaiOauthService.stub(:new, -> { fake_oauth }) do
      get user_settings_openai_oauth_connect_path
      post user_settings_openai_oauth_device_poll_path, as: :json
    end

    assert_response :success
    assert_equal "connected", response.parsed_body["status"]

    setting = @teacher.reload.setting
    assert_equal "oauth-access-new", setting.openai_oauth_access_token
    assert_equal "oauth-refresh-new", setting.openai_oauth_refresh_token
    assert_equal "user_123", setting.openai_oauth_sub
    assert_equal "teacher@example.com", setting.openai_oauth_email
  end

  private

  def with_default_openai_oauth_env
    yield
  end
end
