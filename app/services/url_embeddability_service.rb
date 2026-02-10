require "net/http"
require "uri"
require "socket"
require "ipaddr"

class UrlEmbeddabilityService
  ValidationError = Class.new(StandardError)

  MAX_HTTP_REDIRECTS = 4
  PRIVATE_OR_RESERVED_RANGES = [
    "0.0.0.0/8",
    "10.0.0.0/8",
    "100.64.0.0/10",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.0.0.0/24",
    "192.0.2.0/24",
    "192.88.99.0/24",
    "192.168.0.0/16",
    "198.18.0.0/15",
    "198.51.100.0/24",
    "203.0.113.0/24",
    "224.0.0.0/4",
    "240.0.0.0/4",
    "::/128",
    "::1/128",
    "::ffff:0:0/96",
    "64:ff9b::/96",
    "100::/64",
    "2001:db8::/32",
    "fc00::/7",
    "fe80::/10",
    "ff00::/8"
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  class << self
    def check(url:, resolved_ip: nil)
      Rails.logger.debug "Checking URL: #{url}"
      safe_resolved_ip = resolved_ip.presence || validate_public_https_url!(url)
      response_payload = fetch_remote_response(url, resolved_ip: safe_resolved_ip)
      response = response_payload[:response]
      final_url = response_payload[:final_url]
      x_frame_options = response["X-Frame-Options"].to_s.strip.presence
      frame_ancestors = csp_frame_ancestors_directive(response["Content-Security-Policy"]).presence

      if x_frame_options_blocks_iframe?(x_frame_options)
        return {
          status: "blocked_xfo",
          reason: "Site blocks embedding via X-Frame-Options.",
          final_url: final_url,
          x_frame_options: x_frame_options,
          csp_frame_ancestors: frame_ancestors
        }
      end

      if frame_ancestors_blocks_iframe?(frame_ancestors)
        return {
          status: "blocked_csp",
          reason: "Site blocks embedding via Content-Security-Policy frame-ancestors.",
          final_url: final_url,
          x_frame_options: x_frame_options,
          csp_frame_ancestors: frame_ancestors
        }
      end

      {
        status: "embeddable",
        reason: "No blocking iframe headers detected.",
        final_url: final_url,
        x_frame_options: x_frame_options,
        csp_frame_ancestors: frame_ancestors
      }
    rescue ValidationError
      raise
    rescue StandardError => e
      {
        status: "unknown",
        reason: "Could not verify embeddability (#{e.class}: #{e.message}).",
        final_url: url.to_s,
        x_frame_options: nil,
        csp_frame_ancestors: nil
      }
    end

    def validate_public_https_url!(url, error_class: ValidationError)
      raise error_class, "URL is required." if url.blank?

      uri = URI.parse(url)
      raise error_class, "URL must use HTTPS." unless uri.scheme.to_s.downcase == "https"
      raise error_class, "URL host is missing." if uri.host.blank?

      host = uri.host
      ip_literal = parse_ip_literal(host)
      if ip_literal
        normalized = normalize_ipaddr(ip_literal)
        raise error_class, "URL host resolves to a private or reserved IP." if private_or_reserved_ip?(normalized)
        return normalized.to_s
      end

      resolve_public_ip!(host, error_class: error_class)
    rescue URI::InvalidURIError
      raise error_class, "Invalid URL format."
    rescue SocketError
      raise error_class, "URL host did not resolve."
    end

    private

    def fetch_remote_response(url, resolved_ip:)
      current_url = url
      current_ip = resolved_ip
      redirects = 0

      loop do
        uri = URI.parse(current_url)
        head_request = Net::HTTP::Head.new(uri.request_uri)
        response = perform_request(uri, head_request, resolved_ip: current_ip)

        if redirect_response?(response)
          if redirects >= MAX_HTTP_REDIRECTS
            raise ValidationError, "Too many redirects while fetching URL metadata."
          end
          current_url, current_ip = follow_redirect(response, current_url)
          redirects += 1
          next
        end

        if response.code.to_i >= 400 || response["Content-Type"].blank?
          get_request = Net::HTTP::Get.new(uri.request_uri)
          get_request["Range"] = "bytes=0-1023"
          response = perform_request(uri, get_request, resolved_ip: current_ip)

          if redirect_response?(response)
            if redirects >= MAX_HTTP_REDIRECTS
              raise ValidationError, "Too many redirects while fetching URL metadata."
            end
            current_url, current_ip = follow_redirect(response, current_url)
            redirects += 1
            next
          end
        end
        Rails.logger.debug "URL #{url} resolved to #{current_url}. Response: #{response.code}"
        return { response: response, final_url: current_url }
      end
    rescue URI::InvalidURIError
      raise ValidationError, "Invalid URL format."
    end

    def follow_redirect(response, current_url)
      location = response["Location"].to_s.strip
      raise ValidationError, "Redirect response missing Location header." if location.blank?

      redirected_url = URI.join(current_url, location).to_s
      redirected_ip = validate_public_https_url!(redirected_url)
      [ redirected_url, redirected_ip ]
    rescue URI::InvalidURIError
      raise ValidationError, "Invalid redirect URL."
    end

    def perform_request(uri, request, resolved_ip:)
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = resolved_ip
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 8
      http.read_timeout = 12
      http.start { |client| client.request(request) }
    end

    def redirect_response?(response)
      [ 301, 302, 303, 307, 308 ].include?(response.code.to_i)
    end

    def x_frame_options_blocks_iframe?(header_value)
      value = header_value.to_s.downcase.strip
      return false if value.blank?

      directives = value.split(",").map(&:strip)
      directives.any? do |directive|
        directive == "deny" || directive == "sameorigin" || directive.start_with?("allow-from")
      end
    end

    def frame_ancestors_blocks_iframe?(frame_ancestors_directive)
      return false if frame_ancestors_directive.blank?

      tokens = frame_ancestors_directive.split(/\s+/)[1..]&.map(&:strip)&.reject(&:blank?) || []
      return true if tokens.empty?
      return true if tokens.any? { |token| token.casecmp("'none'").zero? }
      return false if tokens.any? { |token| permissive_frame_ancestor_token?(token) }

      true
    end

    def csp_frame_ancestors_directive(csp_header)
      csp_header.to_s.split(";").map(&:strip).find do |segment|
        segment.downcase.start_with?("frame-ancestors ") || segment.downcase == "frame-ancestors"
      end
    end

    def permissive_frame_ancestor_token?(token)
      normalized = token.to_s.downcase
      normalized == "*" || normalized == "http:" || normalized == "https:"
    end

    def resolve_public_ip!(host, error_class:)
      addresses = Socket.getaddrinfo(host, nil, Socket::AF_UNSPEC, Socket::SOCK_STREAM).map { |entry| entry[3] }.uniq
      raise error_class, "URL host did not resolve." if addresses.empty?

      parsed_ips = addresses.filter_map do |address|
        ip = parse_ip_literal(address)
        ip ? normalize_ipaddr(ip) : nil
      end.uniq(&:to_s)
      raise error_class, "URL host did not resolve." if parsed_ips.empty?

      parsed_ips.each do |ip|
        raise error_class, "URL host resolves to a private or reserved IP." if private_or_reserved_ip?(ip)
      end

      (parsed_ips.find(&:ipv4?) || parsed_ips.first).to_s
    end

    def parse_ip_literal(value)
      IPAddr.new(value)
    rescue StandardError
      nil
    end

    def normalize_ipaddr(ip)
      ip.ipv4_mapped? ? ip.native : ip
    end

    def private_or_reserved_ip?(ip)
      PRIVATE_OR_RESERVED_RANGES.any? { |range| range.include?(ip) }
    end
  end
end
