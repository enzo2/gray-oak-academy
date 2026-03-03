require "test_helper"

class PythonCodeExecutorServiceTest < ActiveSupport::TestCase
  test "execute returns parsed json on success and error hash on request failure" do
    http_client = Object.new
    http_client.define_singleton_method(:request) do |_request|
      Object.new.tap do |response|
        response.define_singleton_method(:body) { '{"final_expression":2,"success":true}' }
        response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      end
    end

    Net::HTTP.stub(:new, http_client) do
      result = PythonCodeExecutorService.execute("print(1+1)")
      assert_equal true, result["success"]
      assert_equal 2, result["final_expression"]
    end

    Net::HTTP.stub(:new, ->(_host, _port) { raise "connection failed" }) do
      result = PythonCodeExecutorService.execute("print(1+1)")
      assert_includes result[:error] || result["error"], "connection failed"
    end
  end
end
