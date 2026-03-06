require "test_helper"
class OpenaiOauthServiceTest < ActiveSupport::TestCase
  FakeSuccessResponse = Struct.new(:body, :code) do
    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end
  end

  FakeErrorResponse = Struct.new(:body, :code) do
    def is_a?(klass)
      false
    end
  end

  test "configured? uses the built-in public client" do
    assert OpenaiOauthService.configured?
    assert_nil OpenaiOauthService.configuration_error
    assert_equal OpenaiOauthService::DEFAULT_CLIENT_ID, OpenaiOauthService.client_id
    assert_equal OpenaiOauthService::PUBLIC_CLIENT_SCOPES, OpenaiOauthService.scopes
  end

  test "start_device_authorization requests device code and returns verifier" do
    captured_content_type = nil
    captured_accept = nil
    captured_body = nil
    captured_uri = nil
    service = OpenaiOauthService.new
    response = FakeSuccessResponse.new(
      {
        "device_code" => "device-code-123",
        "user_code" => "ABCD-EFGH",
        "verification_uri" => "https://auth.openai.com/codex/device",
        "expires_in" => 900,
        "interval" => 5
      }.to_json,
      "200"
    )

    service.stub(:perform_request, ->(uri, method: :get, &block) {
      captured_uri = uri
      request = Net::HTTP::Post.new(uri.request_uri)
      block.call(request)
      captured_content_type = request["Content-Type"]
      captured_accept = request["Accept"]
      captured_body = request.body
      response
    }) do
      payload = service.start_device_authorization

      assert_equal "device-code-123", payload[:device_code]
      assert_equal "ABCD-EFGH", payload[:user_code]
      assert_equal "https://auth.openai.com/codex/device", payload[:verification_uri]
      assert_equal 900, payload[:expires_in]
      assert_equal 5, payload[:interval]
    end

    assert_equal "/api/accounts/deviceauth/usercode?model=codex-mini-latest", captured_uri.request_uri
    assert_equal "application/json", captured_content_type
    assert_equal "application/json", captured_accept
    assert_includes captured_body, "\"client_id\":\"#{OpenaiOauthService::DEFAULT_CLIENT_ID}\""
    refute_includes captured_body, "code_challenge"
  end

  test "start_device_authorization accepts device_auth_id response shape" do
    service = OpenaiOauthService.new
    response = FakeSuccessResponse.new(
      {
        "device_auth_id" => "device-auth-123",
        "user_code" => "WXYZ-1234",
        "expires_in" => 900,
        "interval" => 5
      }.to_json,
      "200"
    )

    service.stub(:perform_request, ->(_uri, method: :get, &block) {
      request = Net::HTTP::Post.new("/api/accounts/deviceauth/usercode")
      block.call(request)
      response
    }) do
      payload = service.start_device_authorization

      assert_equal "device-auth-123", payload[:device_code]
      assert_equal "WXYZ-1234", payload[:user_code]
      assert_equal "https://auth.openai.com/codex/device", payload[:verification_uri]
      assert_equal 900, payload[:expires_in]
      assert_equal 5, payload[:interval]
    end
  end

  test "start_device_authorization falls back to absolute expiry and default interval" do
    service = OpenaiOauthService.new
    future_time = 12.minutes.from_now.change(usec: 0)
    response = FakeSuccessResponse.new(
      {
        "device_auth_id" => "device-auth-123",
        "user_code" => "WXYZ-1234",
        "expires_at" => future_time.iso8601
      }.to_json,
      "200"
    )

    freeze_time do
      service.stub(:perform_request, ->(_uri, method: :get, &block) {
        request = Net::HTTP::Post.new("/api/accounts/deviceauth/usercode")
        block.call(request)
        response
      }) do
        payload = service.start_device_authorization

        assert_in_delta 12.minutes.to_i, payload[:expires_in], 1
        assert_equal 5, payload[:interval]
      end
    end
  end

  test "poll_device_authorization returns authorization code" do
    captured_body = nil
    service = OpenaiOauthService.new
    response = FakeSuccessResponse.new(
      {
        "authorization_code" => "auth-code-123",
        "code_verifier" => "verifier-123",
        "code_challenge" => "challenge-123"
      }.to_json,
      "200"
    )

    service.stub(:perform_request, ->(uri, method: :get, &block) {
      request = Net::HTTP::Post.new(uri.request_uri)
      block.call(request)
      captured_body = request.body
      response
    }) do
      payload = service.poll_device_authorization(device_code: "device-code-123", user_code: "ABCD-EFGH")
      assert_equal "auth-code-123", payload[:authorization_code]
      assert_equal "verifier-123", payload[:code_verifier]
      assert_equal "challenge-123", payload[:code_challenge]
    end

    assert_includes captured_body, "\"device_auth_id\":\"device-code-123\""
    assert_includes captured_body, "\"user_code\":\"ABCD-EFGH\""
    refute_includes captured_body, "grant_type"
  end

  test "poll_device_authorization treats unknown authorization as pending" do
    service = OpenaiOauthService.new
    response = FakeErrorResponse.new(
      {
        "message" => "Device authorization is unknown. Please try again.",
        "type" => "invalid_request_error",
        "code" => "deviceauth_authorization_unknown"
      }.to_json,
      "400"
    )

    service.stub(:perform_request, ->(uri, method: :get, &block) {
      request = Net::HTTP::Post.new(uri.request_uri)
      block.call(request)
      response
    }) do
      assert_raises(OpenaiOauthService::AuthorizationPendingError) do
        service.poll_device_authorization(device_code: "device-code-123", user_code: "ABCD-EFGH")
      end
    end
  end

  test "exchange_code posts urlencoded form payload" do
    captured_accept = nil
    captured_content_type = nil
    captured_body = nil
    service = OpenaiOauthService.new
    response = FakeSuccessResponse.new({ "access_token" => "tok" }.to_json, "200")

    service.stub(:perform_request, ->(_uri, method: :get, &block) {
      request = Net::HTTP::Post.new("/oauth/token")
      block.call(request)
      captured_accept = request["Accept"]
      captured_content_type = request["Content-Type"]
      captured_body = request.body
      response
    }) do
      payload = service.exchange_code(
        code: "auth_code_123",
        code_verifier: "verifier_123",
        redirect_uri: OpenaiOauthService::DEVICE_AUTH_REDIRECT_URI
      )

      assert_equal "tok", payload["access_token"]
    end

    assert_equal "application/json", captured_accept
    assert_equal "application/x-www-form-urlencoded", captured_content_type
    assert_includes captured_body, "grant_type=authorization_code"
    assert_includes captured_body, "code=auth_code_123"
    assert_includes captured_body, "code_verifier=verifier_123"
    assert_includes captured_body, "redirect_uri=https%3A%2F%2Fauth.openai.com%2Fdeviceauth%2Fcallback"
  end

  test "extract_userinfo returns claims from id_token" do
    service = OpenaiOauthService.new
    header = Base64.urlsafe_encode64({ alg: "none" }.to_json, padding: false)
    claims = Base64.urlsafe_encode64({ sub: "user_123", email: "teacher@example.com" }.to_json, padding: false)
    id_token = "#{header}.#{claims}.signature"

    userinfo = service.extract_userinfo(token_payload: { id_token: id_token })

    assert_equal "user_123", userinfo[:sub]
    assert_equal "teacher@example.com", userinfo[:email]
  end

  test "extract_userinfo returns nil when id_token is missing" do
    service = OpenaiOauthService.new

    assert_nil service.extract_userinfo(token_payload: { access_token: "tok" })
  end
end
