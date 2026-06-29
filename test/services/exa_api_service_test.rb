require "test_helper"

class ExaApiServiceTest < ActiveSupport::TestCase
  setup do
    @app = AppSetting.first
    @app.update!(exa_api_key: "exa-test-key")
    @user = users(:admin)
  end

  test "search posts query and options to Exa search endpoint" do
    captured = {}
    with_stubbed_http(captured: captured, response_code: "200", response_body: { results: [ { url: "https://example.com" } ] }.to_json) do
      service = ExaApiService.new
      result = service.search(query: "refraction demos", numResults: 3)

      assert_equal "https://example.com", result["results"][0]["url"]
      assert_equal "api.exa.ai", captured[:host]
      assert_equal "/search", captured[:request_path]

      body = JSON.parse(captured[:request_body])
      assert_equal "refraction demos", body["query"]
      assert_equal 3, body["numResults"]
      assert_equal 1200, body.dig("contents", "highlights", "maxCharacters")
      assert_equal [ "exa-test-key" ], captured[:request_headers]["x-api-key"]
    end
  end

  test "answer posts query and options to Exa answer endpoint" do
    captured = {}
    with_stubbed_http(captured: captured, response_code: "200", response_body: { answer: "Light bends when entering a different medium." }.to_json) do
      service = ExaApiService.new
      result = service.answer(query: "Why does light refract?", text: false)

      assert_equal "Light bends when entering a different medium.", result["answer"]
      assert_equal "/answer", captured[:request_path]

      body = JSON.parse(captured[:request_body])
      assert_equal "Why does light refract?", body["query"]
      assert_equal false, body["text"]
    end
  end

  test "get_contents posts urls to contents endpoint" do
    captured = {}
    with_stubbed_http(captured: captured, response_code: "200", response_body: { results: [] }.to_json) do
      service = ExaApiService.new
      service.get_contents(urls: [ "https://example.com/a" ], text: true)

      assert_equal "/contents", captured[:request_path]
      body = JSON.parse(captured[:request_body])
      assert_equal [ "https://example.com/a" ], body["urls"]
      assert_equal true, body["text"]
    end
  end

  test "deep_research posts deep reasoning search with structured output schema" do
    captured = {}
    schema = {
      type: "object",
      properties: {
        source_anchors: { type: "array", items: { type: "object" } }
      }
    }
    with_stubbed_http(
      captured: captured,
      response_code: "200",
      response_body: { output: { content: { source_anchors: [] } } }.to_json
    ) do
      service = ExaApiService.new
      result = service.deep_research(
        query: "Summarize recent curriculum studies",
        output_schema: schema,
        system_prompt: "Return curriculum research only.",
        numResults: 8,
        type: "keyword"
      )

      assert_equal [], result.dig("output", "content", "source_anchors")
      assert_equal "/search", captured[:request_path]
      body = JSON.parse(captured[:request_body])
      assert_equal "Summarize recent curriculum studies", body["query"]
      assert_equal "deep-reasoning", body["type"]
      assert_equal schema.deep_stringify_keys, body["outputSchema"]
      assert_equal "Return curriculum research only.", body["systemPrompt"]
      assert_equal 8, body["numResults"]
    end
  end

  test "raises clear error on Exa API failure" do
    captured = {}
    with_stubbed_http(captured: captured, response_code: "401", response_body: { error: { message: "invalid key" } }.to_json) do
      service = ExaApiService.new
      error = assert_raises(OpenAiError) do
        service.search(query: "test")
      end

      assert_includes error.message, "Exa API request failed (401)"
      assert_includes error.message, "invalid key"
    end
  end

  test "does not retry transient status errors for POST requests" do
    responses = [
      Struct.new(:code, :body).new("429", { error: { message: "rate limited" } }.to_json),
      Struct.new(:code, :body).new("200", { results: [ { url: "https://retry-success.test" } ] }.to_json)
    ]
    request_count = 0
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_value| }
    http.define_singleton_method(:open_timeout=) { |_value| }
    http.define_singleton_method(:read_timeout=) { |_value| }
    http.define_singleton_method(:write_timeout=) { |_value| }
    http.define_singleton_method(:request) do |_request|
      request_count += 1
      responses.shift
    end

    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |_host, _port| http }

    service = ExaApiService.new
    error = assert_raises(OpenAiError) { service.search(query: "retry test") }

    assert_includes error.message, "(429)"
    assert_equal 1, request_count
  ensure
    Net::HTTP.define_singleton_method(:new, &original_new.to_proc)
  end

  test "raises clear error on POST network timeout without retrying" do
    request_count = 0
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_value| }
    http.define_singleton_method(:open_timeout=) { |_value| }
    http.define_singleton_method(:read_timeout=) { |_value| }
    http.define_singleton_method(:write_timeout=) { |_value| }
    http.define_singleton_method(:request) do |_request|
      request_count += 1
      raise Net::ReadTimeout, "timed out"
    end

    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |_host, _port| http }

    service = ExaApiService.new
    error = assert_raises(OpenAiError) do
      service.deep_research(query: "Create curriculum research.", output_schema: { type: "object" })
    end

    assert_includes error.message, "timed out"
    assert_equal 1, request_count
  ensure
    Net::HTTP.define_singleton_method(:new, &original_new.to_proc)
  end

  test "requires Exa API key" do
    @app.update!(exa_api_key: nil)
    original_exa_key = ENV["EXA_API_KEY"]
    ENV.delete("EXA_API_KEY")

    error = assert_raises(OpenAiError) { ExaApiService.new(api_key: nil) }
    assert_includes error.message, "Exa API key is not configured"
  ensure
    ENV["EXA_API_KEY"] = original_exa_key
  end

  test "logs completion usage when Exa returns costDollars and user context is present" do
    captured = {}
    with_stubbed_http(
      captured: captured,
      response_code: "200",
      response_body: {
        id: "resp_exa",
        costDollars: { total: 0.25068875, reasoningTokens: 123 }
      }.to_json
    ) do
      service = ExaApiService.new(current_user: @user)

      assert_difference -> { Completion.count }, 1 do
        service.deep_research(query: "Analyze top 5 reading interventions", output_schema: { type: "object" })
      end
    end

    completion = Completion.order(:created_at).last
    assert_equal @user.id, completion.user_id
    assert_equal "exa-search-deep-reasoning", completion.model
    assert_equal "https://api.exa.ai/", completion.api_provider
    assert_equal 123, completion.reasoning_tokens
    assert completion.total_cost.present?
  end

  private

  def with_stubbed_http(captured:, response_code:, response_body:)
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_value| }
    http.define_singleton_method(:open_timeout=) { |_value| }
    http.define_singleton_method(:read_timeout=) { |_value| }
    http.define_singleton_method(:write_timeout=) { |_value| }
    http.define_singleton_method(:request) do |request|
      captured[:request_path] = request.path
      captured[:request_headers] = request.to_hash
      captured[:request_body] = request.body
      Struct.new(:code, :body).new(response_code, response_body)
    end

    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |host, port|
      captured[:host] = host
      captured[:port] = port
      http
    end

    yield
  ensure
    Net::HTTP.define_singleton_method(:new, &original_new.to_proc)
  end
end
