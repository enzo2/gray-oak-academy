class OpenaiOauthService
  require "json"
  require "net/http"
  require "uri"

  class Error < StandardError; end

  AUTH_BASE_URI = "https://auth.openai.com".freeze
  CODEX_RESPONSES_BASE_URI = SupportedApi::OPENAI_CODEX_BASE_URI
  TOKEN_PATH = "/oauth/token".freeze
  DEVICE_AUTH_USER_CODE_PATH = "/api/accounts/deviceauth/usercode".freeze
  DEVICE_AUTH_TOKEN_PATH = "/api/accounts/deviceauth/token".freeze
  DEVICE_AUTH_VERIFICATION_PATH = "/codex/device".freeze
  DEVICE_AUTH_REDIRECT_URI = "#{AUTH_BASE_URI}/deviceauth/callback".freeze
  DEVICE_AUTH_MODEL = "codex-mini-latest".freeze
  DEVICE_AUTH_DEFAULT_EXPIRES_IN_SECONDS = 900
  DEVICE_AUTH_DEFAULT_INTERVAL_SECONDS = 5
  DEFAULT_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann".freeze
  PUBLIC_CLIENT_SCOPES = "openid profile email offline_access api.connectors.read api.connectors.invoke".freeze
  HTTP_OPEN_TIMEOUT_SECONDS = 8
  HTTP_READ_TIMEOUT_SECONDS = 15

  def self.configured?
    client_id.present?
  end

  def self.client_id
    DEFAULT_CLIENT_ID
  end

  def self.scopes
    PUBLIC_CLIENT_SCOPES
  end

  def self.default_client?
    true
  end

  def self.configuration_error
    return if client_id.present?

    "OpenAI OAuth is not configured."
  end

  class AuthorizationPendingError < Error; end
  class SlowDownError < Error; end
  class ExpiredTokenError < Error; end
  class AccessDeniedError < Error; end

  def start_device_authorization
    ensure_configured!

    uri = URI.parse("#{AUTH_BASE_URI}#{DEVICE_AUTH_USER_CODE_PATH}")
    uri.query = URI.encode_www_form(model: DEVICE_AUTH_MODEL)
    payload = {
      client_id: self.class.client_id
    }

    response = perform_request(uri, method: :post) do |request|
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json
    end

    parsed = parse_json_response(response, endpoint: uri.to_s)
    parsed = parsed.with_indifferent_access
    device_identifier = parsed[:device_code].presence || parsed[:device_auth_id].presence
    raise Error, "OpenAI device auth did not return a device identifier." if device_identifier.blank?
    expires_in = resolve_device_auth_expires_in(parsed)
    interval = parsed[:interval].presence.to_i
    interval = DEVICE_AUTH_DEFAULT_INTERVAL_SECONDS if interval <= 0

    {
      device_code: device_identifier,
      user_code: parsed[:user_code].presence || parsed[:code].presence,
      verification_uri: parsed[:verification_uri].presence || "#{AUTH_BASE_URI}#{DEVICE_AUTH_VERIFICATION_PATH}",
      expires_in: expires_in,
      interval: interval
    }
  end

  def poll_device_authorization(device_code:, user_code:)
    ensure_configured!
    uri = URI.parse("#{AUTH_BASE_URI}#{DEVICE_AUTH_TOKEN_PATH}")
    payload = {
      device_auth_id: device_code,
      user_code: user_code
    }

    response = perform_request(uri, method: :post) do |request|
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json
    end

    parsed = JSON.parse(response.body.to_s.presence || "{}").with_indifferent_access
    if response.is_a?(Net::HTTPSuccess)
      return {
        authorization_code: parsed.fetch(:authorization_code),
        code_verifier: parsed.fetch(:code_verifier),
        code_challenge: parsed[:code_challenge]
      }
    end

    error = parsed[:error].to_s
    error_code = parsed[:code].to_s
    case error
    when "authorization_pending"
      raise AuthorizationPendingError, error
    when "slow_down"
      raise SlowDownError, error
    when "expired_token"
      raise ExpiredTokenError, error
    when "access_denied"
      raise AccessDeniedError, error
    else
      if error_code == "deviceauth_authorization_unknown"
        raise AuthorizationPendingError, error_code
      end

      raise Error, parsed[:error_description].presence || error.presence || "device authorization failed"
    end
  rescue JSON::ParserError => e
    raise Error, "OpenAI device auth returned invalid JSON: #{e.message}"
  end

  def exchange_device_authorization_code(authorization_code:, code_verifier:)
    exchange_code(
      code: authorization_code,
      code_verifier: code_verifier,
      redirect_uri: DEVICE_AUTH_REDIRECT_URI
    )
  end

  def exchange_code(code:, code_verifier:, redirect_uri:)
    ensure_configured!
    payload = {
      grant_type: "authorization_code",
      code: code,
      code_verifier: code_verifier,
      redirect_uri: redirect_uri,
      client_id: self.class.client_id
    }
    token_request(payload)
  end

  def refresh_access_token(refresh_token:)
    ensure_configured!
    payload = {
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: self.class.client_id
    }
    token_request(payload)
  end

  def extract_userinfo(token_payload:)
    payload = token_payload.to_h.with_indifferent_access
    id_token = payload[:id_token].to_s
    return nil if id_token.blank?

    segments = id_token.split(".")
    return nil if segments.length < 2

    claims_json = Base64.urlsafe_decode64(base64url_segment_with_padding(segments[1]))
    claims = JSON.parse(claims_json).with_indifferent_access
    return nil if claims.blank?

    {
      sub: claims[:sub].presence,
      email: claims[:email].presence
    }.compact.presence
  rescue ArgumentError, JSON::ParserError
    nil
  end

  private

  def ensure_configured!
    message = self.class.configuration_error
    raise Error, message if message.present?
  end

  def token_request(payload)
    uri = URI.join(AUTH_BASE_URI, TOKEN_PATH)
    response = perform_request(uri, method: :post) do |request|
      request["Accept"] = "application/json"
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(payload)
    end

    parsed = parse_json_response(response, endpoint: uri.to_s)
    access_token = parsed["access_token"].to_s
    raise Error, "OpenAI OAuth did not return an access token." if access_token.blank?

    parsed
  end

  def perform_request(uri, method: :get)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = HTTP_OPEN_TIMEOUT_SECONDS
    http.read_timeout = HTTP_READ_TIMEOUT_SECONDS

    request = case method
    when :post
      Net::HTTP::Post.new(uri.request_uri)
    else
      Net::HTTP::Get.new(uri.request_uri)
    end

    yield request if block_given?
    http.request(request)
  end

  def parse_json_response(response, endpoint:)
    body = response.body.to_s
    parsed = JSON.parse(body.presence || "{}")
    return parsed if response.is_a?(Net::HTTPSuccess)

    error_message = parsed.dig("error_description").presence ||
      parsed.dig("error", "message").presence ||
      parsed["error"].to_s.presence ||
      "HTTP #{response.code} (content-type=#{response['Content-Type'].to_s.presence || 'unknown'})"
    raise Error, "#{error_message}; endpoint=#{endpoint}"
  rescue JSON::ParserError => e
    content_type = response["Content-Type"].to_s.presence || "unknown"
    headers = summarized_response_headers(response)
    snippet = body.to_s.strip.gsub(/\s+/, " ").first(240)
    raise Error,
      "OpenAI OAuth returned invalid JSON: #{e.message}; endpoint=#{endpoint}; status=#{response.code}; " \
      "content_type=#{content_type}; headers=#{headers}; body=#{snippet.inspect}"
  end

  def base64url_segment_with_padding(segment)
    padding = (4 - (segment.length % 4)) % 4
    "#{segment}#{'=' * padding}"
  end

  def summarized_response_headers(response)
    [ "location", "set-cookie", "server", "via", "cf-ray", "x-request-id", "x-vercel-id", "cache-control" ].filter_map do |name|
      value = response[name]
      next if value.blank?

      "#{name}=#{value.to_s.first(120).inspect}"
    end.join(", ").presence || "none"
  end

  def resolve_device_auth_expires_in(parsed)
    expires_in = parsed[:expires_in].presence.to_i
    return expires_in if expires_in.positive?

    absolute_expiry = parsed[:expires_at].presence || parsed[:expires_on].presence
    if absolute_expiry.present?
      absolute_time = Time.zone.parse(absolute_expiry.to_s)
      seconds_remaining = (absolute_time - Time.current).to_i
      return seconds_remaining if seconds_remaining.positive?
    end

    DEVICE_AUTH_DEFAULT_EXPIRES_IN_SECONDS
  rescue ArgumentError
    DEVICE_AUTH_DEFAULT_EXPIRES_IN_SECONDS
  end
end
