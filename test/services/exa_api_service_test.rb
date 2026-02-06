require "test_helper"

class ExaApiServiceTest < ActiveSupport::TestCase
  setup do
    @app = AppSetting.first
    @app.update!(exa_api_key: "exa-test-key", exa_research_model: "exa-research")
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
      assert_equal [ "exa-test-key" ], captured[:request_headers]["x-api-key"]
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

  test "responses_research posts to responses endpoint" do
    captured = {}
    with_stubbed_http(captured: captured, response_code: "200", response_body: { id: "resp_1" }.to_json) do
      service = ExaApiService.new
      result = service.responses_research(input: "Summarize recent curriculum studies")

      assert_equal "resp_1", result["id"]
      assert_equal "/responses", captured[:request_path]
      body = JSON.parse(captured[:request_body])
      assert_equal "exa-research", body["model"]
      assert_equal "Summarize recent curriculum studies", body["input"]
    end
  end

  test "wait_for_research polls until completion" do
    service = ExaApiService.new
    responses = [ { "status" => "running" }, { "status" => "completed", "output" => "done" } ]

    service.stub(:get_research, ->(research_id:, stream: nil, events: nil) { responses.shift }) do
      result = service.wait_for_research(research_id: "res_1", timeout_seconds: 5, poll_interval_seconds: 0)
      assert_equal "completed", result["status"]
      assert_equal "done", result["output"]
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
        model: "exa-research",
        costDollars: { total: 0.25068875, reasoningTokens: 123 }
      }.to_json
    ) do
      service = ExaApiService.new(current_user: @user)

      assert_difference -> { Completion.count }, 1 do
        service.responses_research(input: "Analyze top 5 reading interventions")
      end
    end

    completion = Completion.order(:created_at).last
    assert_equal @user.id, completion.user_id
    assert_equal "exa-research", completion.model
    assert_equal "https://api.exa.ai/", completion.api_provider
    assert_equal 123, completion.reasoning_tokens
    assert completion.total_cost.present?
  end

  private

  def with_stubbed_http(captured:, response_code:, response_body:)
    http = Object.new
    http.define_singleton_method(:use_ssl=) { |_value| }
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
