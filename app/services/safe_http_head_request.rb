require "ipaddr"
require "net/http"
require "openssl"
require "uri"

class SafeHttpHeadRequest
  class InvalidUrlError < StandardError; end
  class UnsafeAddressError < StandardError; end

  MAX_ADDRESS_ATTEMPTS = 4
  RETRIABLE_REQUEST_ERRORS = [
    IOError,
    SocketError,
    SystemCallError,
    Timeout::Error,
    OpenSSL::SSL::SSLError
  ].freeze

  FORBIDDEN_NETWORKS = %w[
    0.0.0.0/8
    10.0.0.0/8
    100.64.0.0/10
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.0.0.0/24
    192.0.2.0/24
    192.168.0.0/16
    198.18.0.0/15
    198.51.100.0/24
    203.0.113.0/24
    224.0.0.0/4
    240.0.0.0/4
    ::/128
    ::1/128
    64:ff9b::/96
    100::/64
    2001:2::/48
    2001:db8::/32
    2002::/16
    fc00::/7
    fe80::/10
    ff00::/8
  ].map { |network| IPAddr.new(network) }.freeze

  def initialize(url, open_timeout: 5, read_timeout: 10)
    @uri = parse_url(url)
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def call
    addresses = resolve_addresses
    unsafe_address = addresses.find { |address| forbidden_address?(address) }
    raise UnsafeAddressError, "URL resolves to a non-public address" if unsafe_address

    request_from_any(addresses)
  end

  private

  def parse_url(url)
    uri = URI.parse(url.to_s)
    unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      raise InvalidUrlError, "URL must be an HTTP(S) URL without embedded credentials"
    end

    uri
  rescue URI::InvalidURIError
    raise InvalidUrlError, "URL is invalid"
  end

  def resolve_addresses
    addresses = Addrinfo.getaddrinfo(@uri.host, @uri.port, nil, :STREAM)
                        .filter_map(&:ip_address)
                        .uniq
    raise InvalidUrlError, "URL hostname did not resolve" if addresses.empty?

    addresses
  rescue SocketError
    raise InvalidUrlError, "URL hostname did not resolve"
  end

  def forbidden_address?(address)
    ip = IPAddr.new(address)
    ip = ip.native if ip.ipv4_mapped?
    FORBIDDEN_NETWORKS.any? { |network| network.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def request_from_any(addresses)
    last_error = nil

    addresses.first(MAX_ADDRESS_ATTEMPTS).each do |address|
      return request_from(address)
    rescue *RETRIABLE_REQUEST_ERRORS => e
      last_error = e
    end

    raise last_error
  end

  def request_from(address)
    # Disable environment proxy discovery: a proxy would resolve the hostname
    # again and bypass the address validation above.
    http = Net::HTTP.new(@uri.host, @uri.port, nil)
    http.ipaddr = address
    http.use_ssl = @uri.scheme == "https"
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout
    http.request(Net::HTTP::Head.new(@uri.request_uri))
  end
end
