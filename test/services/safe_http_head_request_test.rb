require "test_helper"

class SafeHttpHeadRequestTest < ActiveSupport::TestCase
  FakeAddress = Data.define(:ip_address)

  test "rejects non-http URLs and embedded credentials" do
    assert_raises(SafeHttpHeadRequest::InvalidUrlError) do
      SafeHttpHeadRequest.new("file:///etc/passwd")
    end
    assert_raises(SafeHttpHeadRequest::InvalidUrlError) do
      SafeHttpHeadRequest.new("https://user:password@example.com/image.png")
    end
  end

  test "rejects private, local, reserved, and IPv4-mapped addresses" do
    addresses = %w[
      0.0.0.0
      10.0.0.1
      100.64.0.1
      127.0.0.1
      169.254.169.254
      172.16.0.1
      192.168.0.1
      198.18.0.1
      224.0.0.1
      ::1
      ::ffff:127.0.0.1
      fc00::1
      fe80::1
      ff02::1
    ]

    addresses.each do |address|
      Addrinfo.stub(:getaddrinfo, [ FakeAddress.new(address) ]) do
        assert_raises(SafeHttpHeadRequest::UnsafeAddressError, address) do
          SafeHttpHeadRequest.new("https://example.com/image.png").call
        end
      end
    end
  end

  test "rejects a hostname with mixed public and private DNS answers" do
    resolved = [ FakeAddress.new("93.184.216.34"), FakeAddress.new("127.0.0.1") ]

    Addrinfo.stub(:getaddrinfo, resolved) do
      assert_raises(SafeHttpHeadRequest::UnsafeAddressError) do
        SafeHttpHeadRequest.new("https://example.com/image.png").call
      end
    end
  end

  test "pins the validated IP while retaining the hostname and request target" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response["Content-Type"] = "image/png"
    http = Object.new
    class << http
      attr_accessor :ipaddr, :use_ssl, :open_timeout, :read_timeout
    end
    captured_request = nil
    http.define_singleton_method(:request) do |request|
      captured_request = request
      response
    end

    new_args = nil
    resolved = [ FakeAddress.new("93.184.216.34") ]
    build_http = lambda do |*args|
      new_args = args
      http
    end

    Addrinfo.stub(:getaddrinfo, resolved) do
      Net::HTTP.stub(:new, build_http) do
        result = SafeHttpHeadRequest.new("https://example.com:8443/image.png?size=large").call

        assert_same response, result
      end
    end

    assert_equal [ "example.com", 8443, nil ], new_args
    assert_equal "93.184.216.34", http.ipaddr
    assert_equal true, http.use_ssl
    assert_equal 5, http.open_timeout
    assert_equal 10, http.read_timeout
    assert_instance_of Net::HTTP::Head, captured_request
    assert_equal "/image.png?size=large", captured_request.path
  end

  test "tries another validated address after a connection failure" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    attempted_addresses = []
    resolved = [ FakeAddress.new("2001:4860:4860::8888"), FakeAddress.new("93.184.216.34") ]

    build_http = lambda do |*|
      http = Object.new
      class << http
        attr_accessor :ipaddr, :use_ssl, :open_timeout, :read_timeout
      end
      http.define_singleton_method(:request) do |*|
        attempted_addresses << ipaddr
        raise Errno::ENETUNREACH if attempted_addresses.one?

        response
      end
      http
    end

    Addrinfo.stub(:getaddrinfo, resolved) do
      Net::HTTP.stub(:new, build_http) do
        result = SafeHttpHeadRequest.new("https://example.com/image.png").call

        assert_same response, result
      end
    end

    assert_equal [ "2001:4860:4860::8888", "93.184.216.34" ], attempted_addresses
  end

  test "limits address attempts when every connection fails" do
    resolved = 6.times.map { |index| FakeAddress.new("93.184.216.#{index + 1}") }
    attempts = 0
    http = Object.new
    class << http
      attr_accessor :ipaddr, :use_ssl, :open_timeout, :read_timeout
    end
    http.define_singleton_method(:request) do |*|
      attempts += 1
      raise Errno::ECONNREFUSED
    end

    Addrinfo.stub(:getaddrinfo, resolved) do
      Net::HTTP.stub(:new, ->(*) { http }) do
        assert_raises(Errno::ECONNREFUSED) do
          SafeHttpHeadRequest.new("https://example.com/image.png").call
        end
      end
    end

    assert_equal SafeHttpHeadRequest::MAX_ADDRESS_ATTEMPTS, attempts
  end

  test "rejects hostnames that do not resolve" do
    Addrinfo.stub(:getaddrinfo, ->(*) { raise SocketError }) do
      assert_raises(SafeHttpHeadRequest::InvalidUrlError) do
        SafeHttpHeadRequest.new("https://does-not-resolve.example/image.png").call
      end
    end
  end
end
