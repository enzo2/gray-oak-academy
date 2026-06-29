require "test_helper"

class OpenaiResponsesServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @conversation = conversations(:teacher_generic_conversation)
    @base_uri = "https://api.test/"
    @access_token = "tok"
    @model = "m1"
  end

  test "codex base uri routes through the dedicated codex responses service" do
    service = OpenaiResponsesService.new(
      current_user: @user,
      access_token: @access_token,
      base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      model: @model,
      log_completion: false
    )

    assert_instance_of OpenaiCodexResponsesService, service
  end

  test "codex_stream_error classifies failures by status and usage-limit marker" do
    service = OpenaiResponsesService.new(
      current_user: @user,
      access_token: @access_token,
      base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      model: @model,
      log_completion: false
    )

    # 429 with a usage_limit_reached marker -> recoverable usage-limit error
    resets_at = 1.hour.from_now.to_i
    usage_limit_body = %({"error":{"type":"usage_limit_reached","message":"The usage limit has been reached","plan_type":"plus","resets_at":#{resets_at},"resets_in_seconds":3600}})
    usage_error = service.send(:codex_stream_error, status: "429", content_type: "application/json", body: usage_limit_body)

    assert_instance_of BackgroundAgentConfigResolver::CodexUsageLimitError, usage_error
    assert_includes usage_error.message, "status=429"
    assert_equal "plus", usage_error.plan_type
    assert_equal resets_at, usage_error.resets_at.to_i

    # Non-429 failures and 429s without the marker stay generic OpenAiErrors
    generic_cases = [
      { status: "500", content_type: "text/plain", body: "boom" },
      { status: "429", content_type: "application/json", body: '{"error":{"type":"rate_limit_exceeded","message":"Slow down"}}' }
    ]

    generic_cases.each do |params|
      error = service.send(:codex_stream_error, **params)
      assert_instance_of OpenAiError, error, "expected generic OpenAiError for #{params[:status]} #{params[:body]}"
      assert_not_kind_of BackgroundAgentConfigResolver::CodexUsageLimitError, error
    end
  end

  test "codex_stream_error classifies invalidated tokens as fallback auth errors" do
    @user.setting.update!(
      openai_oauth_access_token: "invalidated-token",
      openai_oauth_refresh_token: "refresh-token",
      openai_oauth_expires_at: 1.hour.from_now.iso8601
    )
    service = OpenaiResponsesService.new(
      current_user: @user,
      access_token: @access_token,
      base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      model: @model,
      log_completion: false
    )
    body = {
      error: {
        message: "Your authentication token has been invalidated. Please try signing in again.",
        type: "invalid_request_error",
        code: "token_invalidated"
      },
      status: 401
    }.to_json

    error = service.send(:codex_stream_error, status: "401", content_type: "text/plain", body: body)

    assert_instance_of BackgroundAgentConfigResolver::CodexAuthenticationError, error
    assert_kind_of BackgroundAgentConfigResolver::CodexFallbackError, error
    assert_includes error.message, "status=401"
    assert_not @user.setting.reload.openai_oauth_connected?
  end

  test "streamed web_search_call and citations survive into last_response_hash when finalize rebuilds from text deltas" do
    # Codex (chatgpt.com) streams web_search_call items and citation annotations as
    # discrete events but ships an empty `output` in response.completed, so the
    # finalize fallback rebuilds output from accumulated text deltas. The captured
    # research must be folded back in so downstream consumers can read it.
    service = OpenaiResponsesService.new(
      current_user: @user,
      access_token: @access_token,
      base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      model: @model,
      provider_native_tools: [ { type: "web_search" } ],
      log_completion: false
    )

    service.send(:capture_stream_output, {
      "type" => "response.output_item.done",
      "item" => {
        "type" => "web_search_call",
        "status" => "completed",
        "action" => { "type" => "search", "query" => "fractions number line standards" }
      }
    })
    service.send(:capture_stream_output, {
      "type" => "response.output_text.annotation.added",
      "annotation" => { "type" => "url_citation", "url" => "https://example.org/x", "title" => "Frac Standards" }
    })
    # Non-research events are ignored.
    service.send(:capture_stream_output, { "type" => "response.output_text.delta", "delta" => "ignored" })

    service.instance_variable_set(:@stream_fallback_text, +'{"lesson_plan": []}')
    service.instance_variable_set(:@last_response_hash, { "id" => "resp_x", "status" => "completed", "output" => [] })

    service.send(:apply_stream_fallback_output_to_last_response)

    output = service.last_response_hash["output"]
    assert_equal [ "web_search_call", "message" ], output.map { |item| item["type"] }
    assert_equal "fractions number line standards", output.first.dig("action", "query")

    message_part = output.last["content"].first
    assert_equal '{"lesson_plan": []}', message_part["text"]
    assert_equal [ "https://example.org/x" ], message_part["annotations"].map { |a| a["url"] }
  end

  test "codex background response preserves streamed function calls when completed output is empty" do
    responses = Object.new
    responses.define_singleton_method(:create) do |**_params|
      flunk("SDK create should not be used for Codex responses")
    end

    client = Object.new
    client.define_singleton_method(:responses) { responses }

    OpenAI::Client.stub(:new, ->(**_kwargs) { client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
        model: @model,
        flow_tools: [
          {
            type: "function",
            name: "add_and_link_resource",
            description: "Add a resource",
            parameters: { type: "object", properties: {}, additionalProperties: false }
          }
        ],
        log_completion: false
      )

      function_call = {
        "type" => "function_call",
        "id" => "fc_1",
        "call_id" => "call_1",
        "name" => "add_and_link_resource",
        "arguments" => "{}"
      }
      completed_response = {
        "id" => "resp_codex_tool_call",
        "status" => "completed",
        "model" => @model,
        "output" => [],
        "usage" => {}
      }

      service.stub(:manual_codex_responses_stream, ->(_request_params, _request_options_param) {
        [
          { "type" => "response.output_item.done", "item" => function_call },
          { "type" => "response.completed", "response" => completed_response }
        ].to_enum
      }) do
        submitted = service.complete(
          [ { role: "user", content: "Find resources" } ],
          background: true
        )
        completed = service.wait_for_response(submitted["id"])

        assert_equal [ function_call ], submitted["output"]
        assert_equal [ function_call ], completed["output"]
      end
    end
  end

  test "stream research capture resets between streamed completions" do
    service = OpenaiResponsesService.new(
      current_user: @user,
      access_token: @access_token,
      base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      model: @model,
      provider_native_tools: [ { type: "web_search" } ],
      log_completion: false
    )

    streams = [
      [
        {
          "type" => "response.output_item.done",
          "item" => {
            "type" => "web_search_call",
            "status" => "completed",
            "action" => { "type" => "search", "query" => "first query" }
          }
        },
        {
          "type" => "response.output_text.annotation.added",
          "annotation" => { "type" => "url_citation", "url" => "https://example.org/first", "title" => "First" }
        },
        { "type" => "response.output_text.delta", "delta" => "First answer" },
        { "type" => "response.completed", "response" => { "id" => "resp_first", "status" => "completed", "model" => @model, "output" => [], "usage" => {} } }
      ],
      [
        { "type" => "response.output_text.delta", "delta" => "Second answer" },
        { "type" => "response.completed", "response" => { "id" => "resp_second", "status" => "completed", "model" => @model, "output" => [], "usage" => {} } }
      ]
    ]

    service.stub(:manual_codex_responses_stream, ->(_request_params, _request_options_param) { streams.shift.to_enum }) do
      assert_equal "First answer", service.complete([ { role: "user", content: "First" } ])
      assert_equal "Second answer", service.complete([ { role: "user", content: "Second" } ])
    end

    output = service.last_response_hash["output"]
    assert_equal [ "message" ], output.map { |item| item["type"] }
    message_part = output.first["content"].first
    assert_equal "Second answer", message_part["text"]
    assert_nil message_part["annotations"]
  end

  test "initialize prefers OpenAI OAuth token over shared/API key for OpenAI provider" do
    @user.setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: @model,
      llm_api_access_token: nil,
      openai_oauth_access_token: "oauth-openai-token",
      openai_oauth_refresh_token: "oauth-refresh-token",
      openai_oauth_expires_at: 1.hour.from_now.iso8601
    )

    captured_client_kwargs = nil
    fake_client = build_responses_client do |_params|
      response_payload("Done", id: "resp_oauth_priority")
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { captured_client_kwargs = kwargs; fake_client }) do
      OpenaiResponsesService.new(
        current_user: @user,
        log_completion: false
      )
    end

    assert_equal "oauth-openai-token", captured_client_kwargs[:api_key]
    assert_equal OpenaiOauthService::CODEX_RESPONSES_BASE_URI, captured_client_kwargs[:base_url]
  end

  test "initialize refreshes expired OpenAI OAuth token before creating client" do
    @user.setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: @model,
      llm_api_access_token: nil,
      openai_oauth_access_token: "oauth-expired-token",
      openai_oauth_refresh_token: "oauth-refresh-token",
      openai_oauth_expires_at: 5.minutes.ago.iso8601
    )

    assert_equal "oauth-expired-token", @user.setting.openai_oauth_access_token
    assert @user.setting.openai_oauth_expired?

    refresh_called = false
    captured_refresh_token = nil
    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:refresh_access_token) do |refresh_token:|
      refresh_called = true
      captured_refresh_token = refresh_token
      {
        "access_token" => "oauth-refreshed-token",
        "refresh_token" => "oauth-refreshed-refresh-token",
        "expires_in" => 3600
      }
    end

    captured_client_kwargs = nil
    fake_client = build_responses_client do |_params|
      response_payload("Done", id: "resp_oauth_refresh")
    end

    OpenaiOauthService.stub(:new, -> { fake_oauth }) do
      OpenAI::Client.stub(:new, ->(**kwargs) { captured_client_kwargs = kwargs; fake_client }) do
        OpenaiResponsesService.new(
          current_user: @user,
          log_completion: false
        )
      end
    end

    assert refresh_called
    assert_equal "oauth-refresh-token", captured_refresh_token
    @user.setting.reload
    assert_equal "oauth-refreshed-token", @user.setting.openai_oauth_access_token
    assert_equal "oauth-refreshed-refresh-token", @user.setting.openai_oauth_refresh_token
    assert @user.setting.openai_oauth_expires_at.present?
    assert_equal "oauth-refreshed-token", captured_client_kwargs[:api_key]
    assert_equal OpenaiOauthService::CODEX_RESPONSES_BASE_URI, captured_client_kwargs[:base_url]
  end

  test "initialize clears invalid OpenAI OAuth and raises when codex provider has no OAuth token" do
    @user.setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: @model,
      llm_api_access_token: nil,
      openai_oauth_access_token: "oauth-expired-token",
      openai_oauth_refresh_token: "oauth-refresh-token",
      openai_oauth_expires_at: 5.minutes.ago.iso8601,
      openai_oauth_sub: "user_before",
      openai_oauth_email: "before@example.com"
    )

    assert_equal "oauth-expired-token", @user.setting.openai_oauth_access_token
    assert @user.setting.openai_oauth_expired?

    refresh_called = false
    captured_refresh_token = nil
    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:refresh_access_token) do |refresh_token:|
      refresh_called = true
      captured_refresh_token = refresh_token
      raise OpenaiOauthService::Error, "invalid_grant"
    end

    OpenaiOauthService.stub(:new, -> { fake_oauth }) do
      error = assert_raises(OpenAiError) do
        OpenaiResponsesService.new(
          current_user: @user,
          log_completion: false
        )
      end
      assert_includes error.message, "ChatGPT Codex provider requires OpenAI OAuth"
    end

    assert refresh_called
    assert_equal "oauth-refresh-token", captured_refresh_token
    @user.setting.reload
    assert_nil @user.setting.openai_oauth_access_token
    assert_nil @user.setting.openai_oauth_refresh_token
    assert_nil @user.setting.openai_oauth_expires_at
    assert_nil @user.setting.openai_oauth_sub
    assert_nil @user.setting.openai_oauth_email
  end

  test "initialize preserves OAuth credentials when refresh fails transiently" do
    @user.setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: @model,
      llm_api_access_token: nil,
      openai_oauth_access_token: "oauth-expired-token",
      openai_oauth_refresh_token: "oauth-refresh-token",
      openai_oauth_expires_at: 5.minutes.ago.iso8601,
      openai_oauth_sub: "user_before",
      openai_oauth_email: "before@example.com"
    )

    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:refresh_access_token) do |refresh_token:|
      assert_equal "oauth-refresh-token", refresh_token
      raise OpenaiOauthService::Error, "temporarily_unavailable"
    end

    OpenaiOauthService.stub(:new, -> { fake_oauth }) do
      error = assert_raises(OpenAiError) do
        OpenaiResponsesService.new(
          current_user: @user,
          log_completion: false
        )
      end
      assert_includes error.message, "ChatGPT Codex provider requires OpenAI OAuth"
    end

    @user.setting.reload
    assert_equal "oauth-expired-token", @user.setting.openai_oauth_access_token
    assert_equal "oauth-refresh-token", @user.setting.openai_oauth_refresh_token
    assert @user.setting.openai_oauth_expires_at.present?
    assert_equal "user_before", @user.setting.openai_oauth_sub
    assert_equal "before@example.com", @user.setting.openai_oauth_email
  end

  test "student-triggered OAuth refresh updates teacher setting and not student row" do
    student = users(:student)
    teacher = student.teacher
    teacher.setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: @model,
      llm_api_access_token: nil,
      openai_oauth_access_token: "teacher-oauth-expired",
      openai_oauth_refresh_token: "teacher-oauth-refresh",
      openai_oauth_expires_at: 5.minutes.ago.iso8601
    )

    student_setting_updated_at = student.setting.updated_at

    assert_equal "teacher-oauth-expired", teacher.setting.openai_oauth_access_token
    assert teacher.setting.openai_oauth_expired?

    refresh_called = false
    captured_refresh_token = nil
    fake_oauth = Object.new
    fake_oauth.define_singleton_method(:refresh_access_token) do |refresh_token:|
      refresh_called = true
      captured_refresh_token = refresh_token
      {
        "access_token" => "teacher-oauth-refreshed",
        "refresh_token" => "teacher-oauth-refresh-2",
        "expires_in" => 3600
      }
    end

    captured_client_kwargs = nil
    fake_client = build_responses_client do |_params|
      response_payload("Done", id: "resp_student_teacher_refresh")
    end

    OpenaiOauthService.stub(:new, -> { fake_oauth }) do
      OpenAI::Client.stub(:new, ->(**kwargs) { captured_client_kwargs = kwargs; fake_client }) do
        OpenaiResponsesService.new(
          current_user: student,
          log_completion: false
        )
      end
    end

    assert refresh_called
    assert_equal "teacher-oauth-refresh", captured_refresh_token
    teacher.setting.reload
    assert_equal "teacher-oauth-refreshed", teacher.setting.openai_oauth_access_token
    assert_equal "teacher-oauth-refresh-2", teacher.setting.openai_oauth_refresh_token
    assert_equal "teacher-oauth-refreshed", captured_client_kwargs[:api_key]
    assert_equal OpenaiOauthService::CODEX_RESPONSES_BASE_URI, captured_client_kwargs[:base_url]
    student.setting.reload
    assert_equal student_setting_updated_at.to_i, student.setting.updated_at.to_i
    assert_nil student.setting.settings["openai_oauth_access_token"]
    assert_nil student.setting.settings["openai_oauth_refresh_token"]
  end

  test "retrieve_response with include uses codex host when OAuth provider is selected" do
    @user.setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: @model,
      llm_api_access_token: nil,
      openai_oauth_access_token: "oauth-openai-token",
      openai_oauth_refresh_token: "oauth-refresh-token",
      openai_oauth_expires_at: 1.hour.from_now.iso8601
    )

    captured = {}
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_value| }
    fake_http.define_singleton_method(:request) do |request|
      captured[:path] = request.path
      captured[:auth] = request["Authorization"]
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.define_singleton_method(:body) { { "id" => "resp_1", "status" => "completed" }.to_json }
      response
    end

    fake_client = build_responses_client do |_params|
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      Net::HTTP.stub(:new, ->(host, port) { captured[:host] = host; captured[:port] = port; fake_http }) do
        service = OpenaiResponsesService.new(current_user: @user, log_completion: false)
        result = service.retrieve_response("resp_1", include: [ "reasoning.encrypted_content" ])
        assert_equal "resp_1", result["id"]
      end
    end

    assert_equal "chatgpt.com", captured[:host]
    assert_includes captured[:path], "/backend-api/codex/responses/resp_1"
    assert_includes captured[:path], "include%5B%5D=reasoning.encrypted_content"
    assert_equal "Bearer oauth-openai-token", captured[:auth]
  end

  test "retrieve_response with include logs raw response body in development" do
    response_body = { "id" => "resp_raw", "status" => "completed" }.to_json

    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_value| }
    fake_http.define_singleton_method(:request) do |_request|
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@read, true)
      response.define_singleton_method(:body) { response_body }
      response
    end

    info_logs = []
    debug_logs = []
    warn_logs = []
    error_logs = []
    fake_logger = Object.new
    fake_logger.define_singleton_method(:debug?) { true }
    fake_logger.define_singleton_method(:info) { |message| info_logs << message }
    fake_logger.define_singleton_method(:debug) { |message| debug_logs << message }
    fake_logger.define_singleton_method(:warn) { |message| warn_logs << message }
    fake_logger.define_singleton_method(:error) { |message| error_logs << message }

    fake_client = build_responses_client { |_params| response_payload("Done") }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      Net::HTTP.stub(:new, ->(_host, _port) { fake_http }) do
        Rails.env.stub(:development?, true) do
          Rails.stub(:logger, fake_logger) do
            service = OpenaiResponsesService.new(
              current_user: @user,
              access_token: @access_token,
              base_uri: @base_uri,
              model: @model,
              log_completion: false
            )

            result = service.retrieve_response(
              "resp_raw",
              include: [ "reasoning.encrypted_content" ]
            )
            assert_equal "resp_raw", result["id"]
          end
        end
      end
    end

    assert info_logs.any? { |message|
      message.include?("Responses API raw response phase=poll_include") &&
        message.include?(response_body)
    }
    assert warn_logs.none?
    assert error_logs.none?
  end

  test "codex OAuth provider omits unsupported background and metadata request params" do
    @user.setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: @model,
      llm_api_access_token: nil,
      openai_oauth_access_token: "oauth-openai-token",
      openai_oauth_refresh_token: "oauth-refresh-token",
      openai_oauth_expires_at: 1.hour.from_now.iso8601
    )

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_codex_omit")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(current_user: @user, log_completion: false)
      service.stub(:manual_codex_responses_stream, lambda { |request_params, _request_options_param|
        captured = request_params
        [
          { "type" => "response.completed", "response" => response_payload("Done", id: "resp_codex_omit") }
        ].to_enum
      }) do
        result = service.complete(
          [ { role: "user", content: "Hello" } ],
          background: true,
          metadata: { "k" => "v" }
        )
        assert_equal "resp_codex_omit", result["id"]
      end
    end

    assert_nil captured[:background]
    assert_nil captured[:metadata]
  end

  test "complete converts string keyed tool call history into Responses input items" do
    captured = nil
    messages = [
      { "role" => "system", "content" => "Custom system prompt" },
      { "role" => "user", "content" => "Find answer" },
      {
        "role" => "assistant",
        "content" => nil,
        "reasoning_details" => [
          {
            "id" => "rs_1",
            "summary" => [ { "type" => "summary_text", "text" => "Need lookup before answering." } ],
            "encrypted_content" => "enc_blob_1"
          }
        ],
        "tool_calls" => [
          { "id" => "call_1", "function" => { "name" => "Lookup", "arguments" => "{\"query\":\"x\"}" } }
        ]
      },
      { "role" => "tool", "tool_call_id" => "call_1", "content" => "tool output" }
    ]

    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete(messages)
      assert_equal "Done", result
    end

    assert_nil captured[:instructions]
    assert_equal "developer", captured[:input][0]["role"]
    assert_equal "Custom system prompt", captured[:input][0]["content"]
    assert_equal "user", captured[:input][1]["role"]
    assert_equal "Find answer", captured[:input][1]["content"]
    assert_equal "reasoning", captured[:input][2]["type"]
    assert_equal "rs_1", captured[:input][2]["id"]
    assert_equal "enc_blob_1", captured[:input][2]["encrypted_content"]
    assert_equal "summary_text", captured[:input][2]["summary"][0]["type"]
    assert_equal "Need lookup before answering.", captured[:input][2]["summary"][0]["text"]
    assert_equal "function_call", captured[:input][3]["type"]
    assert_equal "call_1", captured[:input][3]["id"]
    assert_equal "call_1", captured[:input][3]["call_id"]
    assert_equal "Lookup", captured[:input][3]["name"]
    assert_equal "function_call_output", captured[:input][4]["type"]
    assert captured[:input][4]["id"].to_s.start_with?("fco_")
    assert_equal "call_1", captured[:input][4]["call_id"]
    assert_equal "tool output", captured[:input][4]["output"]
    assert_equal({ effort: "low" }, captured[:reasoning])
  end

  test "complete keeps full-history tool output images for Responses providers" do
    captured = nil
    messages = [
      {
        "role" => "tool",
        "tool_call_id" => "call_img",
        "content" => [
          { "type" => "text", "text" => GenerateImageJob::SUCCESS_MESSAGE },
          {
            "type" => "image_url",
            "image_url" => { "url" => "https://example.com/generated.png", "detail" => "high" }
          }
        ]
      }
    ]

    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENROUTER_BASE_URI,
        model: @model,
        log_completion: false
      )
      service.complete(messages)
    end

    output = captured[:input].find { |item| item["type"] == "function_call_output" }["output"]
    assert_equal [ "input_text", "input_image" ], output.map { |part| part["type"] }
    assert_equal GenerateImageJob::SUCCESS_MESSAGE, output.first["text"]
    assert_equal "https://example.com/generated.png", output.second["image_url"]
    assert_equal "high", output.second["detail"]
  end

  test "complete replays provider-native reasoning fields from persisted chat history" do
    captured = nil
    messages = [
      { "role" => "user", "content" => "Find answer" },
      {
        "role" => "assistant",
        "reasoning_details" => [
          {
            "type" => "reasoning",
            "id" => "rs_native",
            "format" => "anthropic-claude-v1",
            "signature" => "opaque-signature",
            "provider_extension" => { "untouched" => true }
          }
        ],
        "tool_calls" => [
          { "id" => "call_1", "function" => { "name" => "Lookup", "arguments" => "{}" } }
        ]
      },
      { "role" => "tool", "tool_call_id" => "call_1", "content" => "tool output" }
    ]
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENROUTER_BASE_URI,
        model: @model,
        log_completion: false
      )
      service.complete(messages)
    end

    reasoning = captured[:input].find { |item| item["type"] == "reasoning" }
    assert_equal "anthropic-claude-v1", reasoning["format"]
    assert_equal "opaque-signature", reasoning["signature"]
    assert_equal({ "untouched" => true }, reasoning["provider_extension"])
  end

  test "SDK normalization keeps undocumented OpenRouter reasoning fields" do
    item = OpenAI::Models::Responses::ResponseReasoningItem.new(
      id: "rs_sdk",
      summary: [],
      type: :reasoning,
      format: "anthropic-claude-v1",
      signature: "opaque-signature"
    )
    service = OpenaiResponsesService.new(
      current_user: @user,
      access_token: @access_token,
      base_uri: SupportedApi::OPENROUTER_BASE_URI,
      model: @model,
      log_completion: false
    )

    normalized = service.send(:normalize_response_hash, item)

    assert_equal "anthropic-claude-v1", normalized["format"]
    assert_equal "opaque-signature", normalized["signature"]
  end

  test "complete ignores id-only reasoning details when converting history" do
    captured = nil
    messages = [
      { "role" => "system", "content" => "Custom system prompt" },
      { "role" => "user", "content" => "Find answer" },
      {
        "role" => "assistant",
        "content" => nil,
        "reasoning_details" => [ { "id" => "rs_tmp_only" } ],
        "tool_calls" => [
          { "id" => "call_1", "function" => { "name" => "Lookup", "arguments" => "{\"query\":\"x\"}" } }
        ]
      },
      { "role" => "tool", "tool_call_id" => "call_1", "content" => "tool output" }
    ]

    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete(messages)
      assert_equal "Done", result
    end

    assert_equal "developer", captured[:input][0]["role"]
    assert_equal "user", captured[:input][1]["role"]
    assert_equal "function_call", captured[:input][2]["type"]
    assert_equal "function_call_output", captured[:input][3]["type"]
    assert captured[:input].none? { |item| item["type"] == "reasoning" }
  end

  test "complete passes explicit instructions for non-chained requests" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      result = service.complete([ { role: "user", content: "Hello" } ], instructions: "Explicit instructions")
      assert_equal "Done", result
    end

    assert_equal "Explicit instructions", captured[:instructions]
    assert_equal "user", captured[:input][0]["role"]
  end

  test "codex provider sends fallback top-level instructions" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
        model: @model,
        log_completion: false
      )

      service.stub(:manual_codex_responses_stream, lambda { |request_params, _request_options_param|
        captured = request_params
        [
          { "type" => "response.completed", "response" => response_payload("Done") }
        ].to_enum
      }) do
        result = service.complete(
          [
            { role: "system", content: "Custom system prompt" },
            { role: "user", content: "Hello" }
          ]
        )
        assert_equal "Done", result
      end
    end

    assert_equal "This is Gray Oak Academy.", captured[:instructions]
    assert_equal "developer", captured[:input][0]["role"]
    assert_equal "Custom system prompt", captured[:input][0]["content"]
    assert_equal "user", captured[:input][1]["role"]
    assert_equal "Hello", captured[:input][1]["content"]
  end

  test "codex provider keeps developer input item while adding fallback instructions" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
        model: @model,
        log_completion: false
      )

      service.stub(:manual_codex_responses_stream, lambda { |request_params, _request_options_param|
        captured = request_params
        [
          { "type" => "response.completed", "response" => response_payload("Done") }
        ].to_enum
      }) do
        result = service.complete(
          nil,
          input: [
            { "role" => "developer", "content" => "Developer guardrails" },
            { "role" => "user", "content" => "Hello" }
          ]
        )
        assert_equal "Done", result
      end
    end

    assert_equal "This is Gray Oak Academy.", captured[:instructions]
    assert_equal 2, captured[:input].length
    assert_equal "developer", captured[:input][0]["role"]
    assert_equal "Developer guardrails", captured[:input][0]["content"]
    assert_equal "user", captured[:input][1]["role"]
    assert_equal "Hello", captured[:input][1]["content"]
  end

  test "codex provider explicitly disables store" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
        model: @model,
        log_completion: false
      )

      service.stub(:manual_codex_responses_stream, lambda { |request_params, _request_options_param|
        captured = request_params
        [
          { "type" => "response.completed", "response" => response_payload("Done") }
        ].to_enum
      }) do
        result = service.complete([ { role: "user", content: "Hello" } ])
        assert_equal "Done", result
      end
    end

    assert_equal false, captured[:store]
    assert_nil captured[:previous_response_id]
  end

  test "codex provider omits temperature" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
        model: @model,
        log_completion: false
      )

      service.stub(:manual_codex_responses_stream, lambda { |request_params, _request_options_param|
        captured = request_params
        [
          { "type" => "response.completed", "response" => response_payload("Done") }
        ].to_enum
      }) do
        result = service.complete([ { role: "user", content: "Hello" } ], temperature: 0.2)
        assert_equal "Done", result
      end
    end

    refute_includes captured.keys, :temperature
  end

  test "codex provider uses manual responses stream path" do
    captured = { manual: 0, sdk_stream: 0 }

    responses = Object.new
    responses.define_singleton_method(:stream) do |**_params|
      captured[:sdk_stream] += 1
      [].to_enum
    end

    client = Object.new
    client.define_singleton_method(:responses) { responses }

    OpenAI::Client.stub(:new, ->(**_kwargs) { client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
        model: @model,
        stream_handler: ->(_event) { },
        log_completion: false
      )
      service.stub(:manual_codex_responses_stream, ->(_request_params, _request_options_param) {
        captured[:manual] += 1
        [].to_enum
      }) do
        service.complete([ { role: "user", content: "Hello" } ])
      end
    rescue OpenAiError
      # No final payload is expected from an empty fake stream.
    end

    assert_equal 1, captured[:manual]
    assert_equal 0, captured[:sdk_stream]
  end

  test "codex provider uses manual stream transport for synchronous structured output" do
    responses = Object.new
    responses.define_singleton_method(:create) do |**_params|
      flunk("SDK create should not be used for Codex responses")
    end

    client = Object.new
    client.define_singleton_method(:responses) { responses }

    OpenAI::Client.stub(:new, ->(**_kwargs) { client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
        model: @model,
        log_completion: false
      )

      response = {
        "id" => "resp_codex_sync",
        "status" => "completed",
        "model" => @model,
        "output" => [
          {
            "type" => "message",
            "content" => [
              { "type" => "output_text", "text" => "{\"outline\":[{\"topic\":\"Origins\",\"description\":\"Early printing methods.\"}]}" }
            ]
          }
        ],
        "usage" => {}
      }

      service.stub(:manual_codex_responses_stream, ->(_request_params, _request_options_param) {
        [
          { "type" => "response.completed", "response" => response }
        ].to_enum
      }) do
        result = service.complete(
          [ { role: "user", content: "Hello" } ],
          response_format: { type: "json_schema", json_schema: { name: "Outline", schema: { "type" => "object" } } }
        )

        assert_equal({ "outline" => [ { "topic" => "Origins", "description" => "Early printing methods." } ] }, result)
      end
    end
  end

  test "codex provider parses streamed text when completed response has no output items" do
    responses = Object.new
    responses.define_singleton_method(:create) do |**_params|
      flunk("SDK create should not be used for Codex responses")
    end

    client = Object.new
    client.define_singleton_method(:responses) { responses }

    OpenAI::Client.stub(:new, ->(**_kwargs) { client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
        model: @model,
        log_completion: false
      )

      completed_response = {
        "id" => "resp_codex_empty_output",
        "status" => "completed",
        "model" => @model,
        "output" => [],
        "usage" => { "total_tokens" => 42 }
      }

      service.stub(:manual_codex_responses_stream, ->(_request_params, _request_options_param) {
        [
          { "type" => "response.output_text.delta", "delta" => "{\"lessons\":[" },
          { "type" => "response.output_text.delta", "delta" => "{\"title\":\"Intro\",\"goals\":\"Start here\",\"duration\":20}" },
          { "type" => "response.output_text.delta", "delta" => "]}" },
          { "type" => "response.completed", "response" => completed_response }
        ].to_enum
      }) do
        result = service.complete(
          [ { role: "user", content: "Create lessons" } ],
          response_format: { type: "json_schema", json_schema: { name: "Lessons", schema: { "type" => "object" } } }
        )

        assert_equal(
          { "lessons" => [ { "title" => "Intro", "goals" => "Start here", "duration" => 20 } ] },
          result
        )
        assert_equal "resp_codex_empty_output", service.last_response_id
        assert_equal "completed", service.last_response_hash["status"]
        assert_equal 42, service.last_response_hash.dig("usage", "total_tokens")
      end
    end
  end

  test "finalize_stream_response synthesizes response from text deltas when completed event is missing" do
    service = OpenaiResponsesService.new(
      current_user: @user,
      access_token: @access_token,
      base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      model: @model,
      stream_handler: ->(_event) { },
      log_completion: false
    )

    service.instance_variable_set(:@stream_fallback_text, +"Fallback text")
    fake_stream = Object.new
    fake_stream.define_singleton_method(:get_final_response) do
      raise RuntimeError, "Didn't receive a 'response.completed' event"
    end

    service.send(:finalize_stream_response, fake_stream)

    assert_equal "completed", service.last_response_hash["status"]
    assert_equal @model, service.last_response_hash["model"]
    assert_equal "Fallback text", service.output_text(service.last_response_hash)
    assert service.last_response_id.start_with?("resp_stream_fallback_")
  end

  test "drain_sse_events parses codex-style SSE frames without relying on content-type" do
    service = OpenaiResponsesService.new(
      current_user: @user,
      access_token: @access_token,
      base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      model: @model,
      log_completion: false
    )
    buffer = <<~SSE
      event: response.created
      data: {"type":"response.created","response":{"id":"resp_1","status":"in_progress"}}

      event: response.output_text.delta
      data: {"type":"response.output_text.delta","delta":"Hello"}

    SSE

    events = service.send(:drain_sse_events!, buffer.dup, flush: true)

    assert_equal 2, events.length
    assert_equal "response.created", events[0]["type"]
    assert_equal "resp_1", events[0].dig("response", "id")
    assert_equal "response.output_text.delta", events[1]["type"]
    assert_equal "Hello", events[1]["delta"]
  end

  test "complete rejects explicit instructions when previous response id is used" do
    fake_client = build_responses_client do |_params|
      flunk("Responses create should not be called when instructions and previous_response_id are combined")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      error = assert_raises(OpenAiError) do
        service.complete(
          [ { role: "user", content: "Hello" } ],
          instructions: "Explicit instructions",
          previous_response_id: "resp_prev"
        )
      end
      assert_includes error.message, "Explicit instructions are not allowed with previous_response_id"
    end
  end

  test "openrouter requests stay stateless and omit store chaining params" do
    @conversation.update!(
      responses_previous_id: "resp_prev",
      responses_provider: "https://openrouter.ai/api/v1/",
      responses_model: @model
    )

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://openrouter.ai/api/v1/",
        model: @model,
        log_completion: false
      )

      refute service.stateful_supported?
      service.complete([ { role: "user", content: "Hello" } ], previous_response_id: "resp_override")
    end

    assert_nil captured[:store]
    assert_nil captured[:previous_response_id]
    assert_equal [ "reasoning.encrypted_content" ], captured[:include]
    assert_equal({ effort: "low" }, captured[:reasoning])
  end

  test "complete merges stateless reasoning include with explicit include fields" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://openrouter.ai/api/v1/",
        model: @model,
        log_completion: false
      )

      service.complete(
        [ { role: "user", content: "Hello" } ],
        include: [ "output_text.logprobs", "reasoning.encrypted_content" ]
      )
    end

    assert_equal [ "output_text.logprobs", "reasoning.encrypted_content" ], captured[:include]
  end

  test "complete defaults reasoning effort to high when reasoning_model is enabled" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        reasoning_model: true,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_equal({ effort: "high" }, captured[:reasoning])
  end

  test "openrouter reasoning model defaults include visible reasoning" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://openrouter.ai/api/v1/",
        model: @model,
        reasoning_model: true,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_equal({ effort: "high", exclude: false }, captured[:reasoning])
  end

  test "xai reasoning model omits reasoning effort parameter" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.x.ai/v1/",
        model: @model,
        reasoning_model: true,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_nil captured[:reasoning]
  end

  test "xai requests support state chaining params" do
    @conversation.update!(
      responses_previous_id: "resp_prev",
      responses_provider: "https://api.x.ai/v1/",
      responses_model: @model
    )

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://api.x.ai/v1/",
        model: @model,
        log_completion: false
      )

      assert service.stateful_supported?
      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_equal true, captured[:store]
    assert_equal "resp_prev", captured[:previous_response_id]
  end

  test "non-openai providers omit background argument even when requested" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_bg_xai")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.example.com/v1/",
        model: @model,
        log_completion: false
      )

      response = service.complete([ { role: "user", content: "Hello" } ], background: true)
      assert_equal "resp_bg_xai", response["id"]
    end

    assert_nil captured[:background]
  end

  test "providers without metadata support omit metadata argument even when requested" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_meta_xai")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.x.ai/v1/",
        model: @model,
        log_completion: false
      )

      response = service.complete(
        [ { role: "user", content: "Hello" } ],
        metadata: { run_id: "run_meta_1", source: "test" }
      )
      assert_equal "Done", response
    end

    assert_nil captured[:metadata]
  end

  test "openrouter keeps metadata argument when requested" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_meta_or")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://openrouter.ai/api/v1/",
        model: @model,
        log_completion: false
      )

      response = service.complete(
        [ { role: "user", content: "Hello" } ],
        metadata: { run_id: "run_meta_or", source: "test" }
      )
      assert_equal "Done", response
    end

    assert_equal "run_meta_or", captured.dig(:metadata, "run_id")
    assert_equal "test", captured.dig(:metadata, "source")
  end

  test "openai metadata is constrained to provider key/value limits" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_meta_openai")
    end

    long_key = "k" * 80
    metadata = {
      run_id: "run_meta_openai",
      task_full: "a" * 600,
      nested: { note: "b" * 700 },
      long_key => "value"
    }
    20.times do |idx|
      metadata["extra_#{idx}"] = idx
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      result = service.complete(
        [ { role: "user", content: "Hello" } ],
        metadata: metadata
      )
      assert_equal "Done", result
    end

    assert_equal 600, metadata[:task_full].length
    assert_equal 700, metadata.dig(:nested, :note).length
    task_full_value = captured.dig(:metadata, "task_full") || captured.dig(:metadata, :task_full)
    nested_value = captured.dig(:metadata, "nested") || captured.dig(:metadata, :nested)
    assert task_full_value.present?, "Expected task_full metadata key, got #{captured[:metadata].inspect}"
    assert nested_value.present?, "Expected nested metadata key, got #{captured[:metadata].inspect}"
    assert_equal 512, task_full_value.length
    assert_equal "a" * 512, task_full_value
    assert_equal 512, nested_value.length
    assert_includes nested_value, "\"note\""
    assert_instance_of String, nested_value
    assert captured[:metadata].keys.all? { |key| key.to_s.length <= 64 }
    assert_operator captured[:metadata].size, :<=, 16
    truncated_key = "k" * 64
    assert_equal "value", captured[:metadata][truncated_key] || captured[:metadata][truncated_key.to_sym]
  end

  test "agent_run mode resolves provider, token, and model from app settings" do
    AppSetting.first.update!(
      background_agent_supported_api_id: supported_apis(:xai).id,
      background_agent_model: "grok-4-0709"
    )

    captured_client_kwargs = nil
    captured_request = nil
    fake_client = build_responses_client do |params|
      captured_request = params
      response_payload("Done", id: "resp_agent")
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { captured_client_kwargs = kwargs; fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        agent_run: true,
        log_completion: false
      )

      result = service.complete([ { role: "user", content: "Hello" } ])
      assert_equal "Done", result
      assert_equal "https://api.x.ai/v1/", service.base_uri
      assert_equal "grok-4-0709", service.model
    end

    assert_equal "xai-test-token", captured_client_kwargs[:api_key]
    assert_equal "https://api.x.ai/v1/", captured_client_kwargs[:base_url]
    assert_equal "grok-4-0709", captured_request[:model]
  end

  test "openrouter agent run uses metadata run id as sticky session header" do
    openrouter = create_openrouter_supported_api
    AppSetting.first.update!(
      background_agent_supported_api_id: openrouter.id,
      background_agent_model: "anthropic/claude-sonnet-4.6"
    )
    captured = nil
    run_id = "sticky-" + ("x" * 300)
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_openrouter_agent").merge("status" => "completed")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        agent_run: true,
        log_completion: false
      )
      service.complete(
        [ { role: "user", content: "Hello" } ],
        background: true,
        metadata: { run_id: run_id, run_type: "test" }
      )
    end

    assert_equal run_id.first(256), captured.dig(:request_options, :extra_headers, "x-session-id")
  end

  test "agent run can still explicitly require a stateful provider" do
    openrouter = create_openrouter_supported_api
    AppSetting.first.update!(
      background_agent_supported_api_id: openrouter.id,
      background_agent_model: "anthropic/claude-sonnet-4.6"
    )

    error = assert_raises(OpenAiError) do
      OpenaiResponsesService.new(
        current_user: @user,
        agent_run: true,
        agent_run_require_stateful: true,
        log_completion: false
      )
    end

    assert_includes error.message, "does not support required stateful Responses behavior"
  end

  test "openrouter ordinary requests omit sticky agent session header" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENROUTER_BASE_URI,
        model: @model,
        log_completion: false
      )
      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_nil captured.dig(:request_options, :extra_headers, "x-session-id")
  end

  test "complete exposes an isolated copy of fully resolved input items" do
    fake_client = build_responses_client { |_params| response_payload("Done") }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENROUTER_BASE_URI,
        model: @model,
        log_completion: false
      )
      service.complete([ { role: "user", content: "Hello" } ])

      first_copy = service.last_input_items
      assert_equal "developer", first_copy.first["role"]
      assert_equal "user", first_copy.second["role"]
      first_copy << { "role" => "user", "content" => "mutated" }
      assert_equal 2, service.last_input_items.size
    end
  end

  test "explicitly disabled reasoning omits encrypted reasoning include" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: SupportedApi::OPENROUTER_BASE_URI,
        model: @model,
        reasoning_model: true,
        log_completion: false
      )
      service.complete(
        [ { role: "user", content: "Hello" } ],
        reasoning: { effort: "none" },
        request_timeout_seconds: 12
      )
    end

    assert_equal({ enabled: false }, captured[:reasoning])
    assert_nil captured[:include]
    assert_equal 12.0, captured.dig(:request_options, :timeout)
  end

  test "agent_run mode rejects unsupported provider overrides" do
    AppSetting.first.update!(background_agent_model: "gpt-5.2")

    error = assert_raises(OpenAiError) do
      OpenaiResponsesService.new(
        current_user: @user,
        base_uri: supported_apis(:example_api).api_base_uri,
        agent_run: true,
        log_completion: false
      )
    end

    assert_includes error.message, "Background agent runs provider https://api.example.com/ is unavailable"
  end

  test "stateful provider helper accepts openai and xai hosts only" do
    assert OpenaiResponsesService.stateful_supported_base_uri?("https://api.openai.com/v1/")
    assert OpenaiResponsesService.stateful_supported_base_uri?("https://api.x.ai/v1/")
    refute OpenaiResponsesService.stateful_supported_base_uri?("https://api.example.com/v1/")
    refute OpenaiResponsesService.stateful_supported_base_uri?("https://openrouter.ai/api/v1/")
  end

  test "complete includes stable prompt cache key for OpenAI Responses chats" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_equal "conversation-#{@conversation.id}", captured[:prompt_cache_key]
  end

  test "complete includes stable prompt cache key for xAI Responses chats" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://api.x.ai/v1/",
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_equal "conversation-#{@conversation.id}", captured[:prompt_cache_key]
  end

  test "complete omits prompt cache key when no conversation is present" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_nil captured[:prompt_cache_key]
  end

  test "auto compaction threshold is 70 percent of context length capped at 200k" do
    assert_equal 140_000, OpenaiResponsesService.auto_compaction_threshold_for_context_length(200_000)
    assert_equal 200_000, OpenaiResponsesService.auto_compaction_threshold_for_context_length(400_000)
    assert_equal 1_000, OpenaiResponsesService.auto_compaction_threshold_for_context_length(999)
    assert_equal 1_000, OpenaiResponsesService.auto_compaction_threshold_for_context_length(1_000)
    assert_nil OpenaiResponsesService.auto_compaction_threshold_for_context_length(nil)
  end

  test "complete includes openai compaction context management by default when context length is known" do
    llm = Struct.new(:context_length).new(200_000)
    @conversation.define_singleton_method(:llm_in_use) { llm }

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_equal(
      [ { type: "compaction", compact_threshold: 140_000 } ],
      captured[:context_management]
    )
  end

  test "complete caps openai auto compaction threshold at 200k" do
    llm = Struct.new(:context_length).new(400_000)
    @conversation.define_singleton_method(:llm_in_use) { llm }

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_equal(
      [ { type: "compaction", compact_threshold: 200_000 } ],
      captured[:context_management]
    )
  end

  test "complete omits compaction context management for unsupported providers" do
    llm = Struct.new(:context_length).new(200_000)
    @conversation.define_singleton_method(:llm_in_use) { llm }

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://openrouter.ai/api/v1/",
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ])
    end

    assert_nil captured[:context_management]
  end

  test "complete omits compaction context management when auto compaction is disabled" do
    llm = Struct.new(:context_length).new(200_000)
    @conversation.define_singleton_method(:llm_in_use) { llm }

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ], auto_compaction: false)
    end

    assert_nil captured[:context_management]
  end

  test "complete logs xAI cost ticks as total cost" do
    fake_client = build_responses_client do |_params|
      response_payload("Priced reply", id: "resp_xai_cost").merge(
        "model" => @model,
        "usage" => {
          "input_tokens" => 199,
          "output_tokens" => 1,
          "total_tokens" => 200,
          "cost_in_usd_ticks" => 200_000_000
        }
      )
    end

    assert_difference -> { Completion.count }, 1 do
      OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          conversation: @conversation,
          access_token: @access_token,
          base_uri: "https://api.x.ai/v1/",
          model: @model
        )

        assert_equal "Priced reply", service.complete([ { role: "user", content: "Hello" } ])
      end
    end

    completion = Completion.order(:created_at).last
    assert_equal "https://api.x.ai/v1/", completion.api_provider
    assert_in_delta 0.02, completion.total_cost.to_f, 0.0001
  end

  test "complete with store false does not write response state to conversation for openai providers" do
    @conversation.update!(
      responses_previous_id: "resp_prev",
      responses_provider: @base_uri,
      responses_model: @model
    )

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ], store: false)
    end

    assert_equal false, captured[:store]
    assert_nil captured[:previous_response_id]

    @conversation.reload
    assert_equal "resp_prev", @conversation.responses_previous_id
    assert_equal @base_uri, @conversation.responses_provider
    assert_equal @model, @conversation.responses_model
  end

  test "complete logs completion using configured model when response model is blank string" do
    fake_client = build_responses_client do |_params|
      {
        "id" => "resp_blank_model",
        "model" => "",
        "output" => [
          {
            "type" => "message",
            "content" => [
              { "type" => "output_text", "text" => "Done" }
            ]
          }
        ],
        "usage" => {}
      }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model
      )

      assert_difference("Completion.count", 1) do
        result = service.complete([ { role: "user", content: "Hello" } ])
        assert_equal "Done", result
      end
    end

    assert_equal @model, Completion.order(:created_at).last.model
  end

  test "complete does not raise on tool-call-only output without text" do
    fake_client = build_responses_client do |_params|
      {
        "id" => "resp_tool_only",
        "model" => @model,
        "output" => [
          { "type" => "function_call", "call_id" => "call_1", "name" => "Lookup", "arguments" => "{}" }
        ],
        "usage" => {}
      }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete([ { role: "user", content: "Find answer" } ])
      assert_equal "", result
      assert_equal "resp_tool_only", service.last_response_id
    end
  end

  test "complete does not raise on empty output without tool calls" do
    fake_client = build_responses_client do |_params|
      {
        "id" => "resp_empty",
        "model" => @model,
        "status" => "completed",
        "output" => [],
        "usage" => {}
      }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete([ { role: "user", content: "Hello" } ])
      assert_equal "", result
      assert_equal "resp_empty", service.last_response_id
    end
  end

  test "complete parses string keyed response_format for structured outputs" do
    fake_client = build_responses_client do |_params|
      response_payload("{\"name\":\"Ada\"}")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete(
        [ { role: "user", content: "Return JSON" } ],
        response_format: { "type" => "json_object" }
      )
      assert_equal({ "name" => "Ada" }, result)
    end
  end

  test "complete extracts valid JSON when output includes earlier invalid brace content" do
    fake_client = build_responses_client do |_params|
      response_payload("Assistant notes: {not valid json} Final output: {\"name\":\"Ada\"}")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete(
        [ { role: "user", content: "Return JSON" } ],
        response_format: { "type" => "json_object" }
      )
      assert_equal({ "name" => "Ada" }, result)
    end
  end

  test "complete with background true returns raw response payload" do
    fake_client = build_responses_client do |_params|
      {
        "id" => "resp_bg",
        "status" => "queued",
        "model" => @model,
        "output" => []
      }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete(
        [ { role: "user", content: "Run long task" } ],
        background: true,
        metadata: { run_id: "run_1" }
      )

      assert_equal "resp_bg", result["id"]
      assert_equal "queued", result["status"]
    end
  end

  test "agent_run background requests execute synchronously and wait_for_response reuses cached terminal response" do
    captured_request = nil
    captured_client_kwargs = nil
    retrieve_called = false

    fake_client = build_responses_client(
      retrieve_proc: lambda { |_response_id, _params|
        retrieve_called = true
        flunk("retrieve should not be called when the submission already returned a terminal response")
      }
    ) do |params|
      captured_request = params
      response_payload("Done", id: "resp_sync").merge("status" => "completed")
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { captured_client_kwargs = kwargs; fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: supported_apis(:xai).api_base_uri,
        model: @model,
        log_completion: false,
        agent_run: true
      )

      submitted = service.complete(
        [ { role: "user", content: "Run long task" } ],
        background: true,
        metadata: { run_id: "run_sync", run_type: "propose_resources" }
      )
      assert_equal "resp_sync", submitted["id"]
      assert_equal "completed", submitted["status"]

      result = service.wait_for_response("resp_sync", timeout_seconds: 5, poll_interval_seconds: 0)
      assert_equal "completed", result["status"]
    end

    assert_nil captured_request[:background]
    assert_nil captured_request[:metadata]
    assert_equal false, retrieve_called
    assert_equal(
      [ OpenaiClientDefaults.timeout_seconds, OpenaiResponsesService::AGENT_RUN_SYNC_TIMEOUT_SECONDS ].max,
      captured_client_kwargs[:timeout]
    )
  end

  test "agent_run on openai keeps background true requests" do
    captured_request = nil
    fake_client = build_responses_client do |params|
      captured_request = params
      { "id" => "resp_bg", "status" => "queued", "model" => @model, "output" => [] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: supported_apis(:openai).api_base_uri,
        model: @model,
        log_completion: false,
        agent_run: true
      )

      result = service.complete(
        [ { role: "user", content: "Run long task" } ],
        background: true,
        metadata: { run_id: "run_openai_bg", run_type: "propose_resources" }
      )
      assert_equal "resp_bg", result["id"]
      assert_equal "queued", result["status"]
    end

    assert_equal true, captured_request[:background]
    assert_equal "run_openai_bg", captured_request.dig(:metadata, "run_id")
    assert_equal "propose_resources", captured_request.dig(:metadata, "run_type")
  end

  test "complete includes provider-native responses tools without enabling app function tools" do
    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        enable_tools: false,
        provider_native_tools: [ { type: "web_search" } ],
        log_completion: false
      )

      result = service.complete([ { role: "user", content: "Find recent refraction demos" } ])
      assert_equal "Done", result
    end

    assert_equal [ { "type" => "web_search" } ], captured[:tools]
  end

  test "wait_for_response polls until completion" do
    call_count = 0
    fake_client = build_responses_client(
      retrieve_proc: lambda { |_response_id, _params|
        call_count += 1
        if call_count == 1
          { "id" => "resp_bg", "status" => "in_progress", "output" => [] }
        else
          response_payload("Done", id: "resp_bg").merge("status" => "completed")
        end
      }
    ) { |_params| response_payload("unused") }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.wait_for_response("resp_bg", timeout_seconds: 5, poll_interval_seconds: 0)
      assert_equal "completed", result["status"]
      assert_equal 2, call_count
    end
  end

  test "background runs without conversation are logged as agent runs" do
    fake_client = build_responses_client(
      retrieve_proc: lambda { |_response_id, _params|
        response_payload("Done", id: "resp_bg").merge("status" => "completed")
      }
    ) do |_params|
      {
        "id" => "resp_bg",
        "status" => "queued",
        "model" => @model,
        "output" => []
      }
    end

    submitted_calls = []
    completed_calls = []
    failed_calls = []
    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**kwargs| submitted_calls << kwargs }
    fake_run_log.define_singleton_method(:record_completed) { |**kwargs| completed_calls << kwargs }
    fake_run_log.define_singleton_method(:record_failed) { |**kwargs| failed_calls << kwargs }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          access_token: @access_token,
          base_uri: supported_apis(:openai).api_base_uri,
          model: @model,
          log_completion: false,
          agent_run: true
        )

        service.complete(
          [ { role: "user", content: "Run long task" } ],
          background: true,
          metadata: { run_id: "run_1", run_type: "propose_resources", source: "propose_resources", task_preview: "Preview task" }
        )
        service.wait_for_response("resp_bg", timeout_seconds: 5, poll_interval_seconds: 0)
      end
    end

    assert_equal 1, submitted_calls.size
    assert_equal "run_1", submitted_calls.first[:run_id]
    assert_equal "resp_bg", submitted_calls.first[:response_id]
    assert_equal supported_apis(:openai).api_base_uri, submitted_calls.first[:provider_base_uri]
    assert_equal "propose_resources", submitted_calls.first[:source]
    assert_equal "Run long task", submitted_calls.first[:prompt]

    assert_equal 1, completed_calls.size
    assert_equal "run_1", completed_calls.first[:run_id]
    assert_equal "resp_bg", completed_calls.first[:response_id]
    assert_equal 0, failed_calls.size
  end

  test "background agent run prompt resets for a new run_id" do
    create_count = 0
    fake_client = build_responses_client do |_params|
      create_count += 1
      {
        "id" => "resp_#{create_count}",
        "status" => "queued",
        "model" => @model,
        "output" => []
      }
    end

    submitted_calls = []
    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**kwargs| submitted_calls << kwargs }
    fake_run_log.define_singleton_method(:record_completed) { |**_kwargs| nil }
    fake_run_log.define_singleton_method(:record_failed) { |**_kwargs| nil }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          access_token: @access_token,
          base_uri: supported_apis(:openai).api_base_uri,
          model: @model,
          log_completion: false,
          agent_run: true
        )

        service.complete(
          [ { role: "user", content: "First run prompt" } ],
          background: true,
          metadata: { run_id: "run_1", run_type: "propose_resources", source: "propose_resources", task_preview: "Preview 1" }
        )
        service.complete(
          [ { role: "user", content: "Second run prompt" } ],
          background: true,
          metadata: { run_id: "run_2", run_type: "propose_resources", source: "propose_resources", task_preview: "Preview 2" }
        )
      end
    end

    assert_equal 2, submitted_calls.size
    assert_equal "run_1", submitted_calls.first[:run_id]
    assert_equal "First run prompt", submitted_calls.first[:prompt]
    assert_equal "run_2", submitted_calls.second[:run_id]
    assert_equal "Second run prompt", submitted_calls.second[:prompt]
  end

  test "background agent run preserves submitted phase from metadata" do
    fake_client = build_responses_client do |_params|
      {
        "id" => "resp_phase",
        "status" => "queued",
        "model" => @model,
        "output" => []
      }
    end

    submitted_calls = []
    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**kwargs| submitted_calls << kwargs }
    fake_run_log.define_singleton_method(:record_completed) { |**_kwargs| nil }
    fake_run_log.define_singleton_method(:record_failed) { |**_kwargs| nil }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          access_token: @access_token,
          base_uri: supported_apis(:openai).api_base_uri,
          model: @model,
          log_completion: false,
          agent_run: true
        )

        service.complete(
          [ { role: "user", content: "Retry turn" } ],
          background: true,
          metadata: {
            run_id: "run_phase",
            run_type: "propose_resources",
            source: "propose_resources",
            phase: "retry"
          }
        )
      end
    end

    assert_equal 1, submitted_calls.size
    assert_equal "retry", submitted_calls.first[:phase]
  end

  test "background agent run prompt does not fall back to metadata task fields" do
    fake_client = build_responses_client do |_params|
      {
        "id" => "resp_no_prompt",
        "status" => "queued",
        "model" => @model,
        "output" => []
      }
    end

    submitted_calls = []
    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**kwargs| submitted_calls << kwargs }
    fake_run_log.define_singleton_method(:record_completed) { |**_kwargs| nil }
    fake_run_log.define_singleton_method(:record_failed) { |**_kwargs| nil }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          access_token: @access_token,
          base_uri: supported_apis(:openai).api_base_uri,
          model: @model,
          log_completion: false,
          agent_run: true
        )

        service.complete(
          nil,
          input: [ { type: "function_call_output", call_id: "call_1", output: "{\"ok\":true}" } ],
          background: true,
          metadata: {
            run_id: "run_no_prompt",
            run_type: "propose_resources",
            source: "propose_resources",
            task_prompt: "This should never be used for agent run logging"
          }
        )
      end
    end

    assert_equal 1, submitted_calls.size
    assert_equal "Background Responses run", submitted_calls.first[:prompt]
  end

  test "background run completion logs aggregate metrics across tool-call turns" do
    create_count = 0
    fake_client = build_responses_client(
      retrieve_proc: lambda { |response_id, _params|
        case response_id
        when "resp_turn_1"
          {
            "id" => "resp_turn_1",
            "status" => "completed",
            "output" => [
              { "type" => "function_call", "call_id" => "call_1", "name" => "exa_search", "arguments" => "{}" }
            ]
          }
        when "resp_turn_2"
          response_payload("Done", id: "resp_turn_2").merge("status" => "completed")
        else
          flunk("Unexpected response_id #{response_id}")
        end
      }
    ) do |_params|
      create_count += 1
      case create_count
      when 1
        { "id" => "resp_turn_1", "status" => "queued", "model" => @model, "output" => [] }
      when 2
        { "id" => "resp_turn_2", "status" => "queued", "model" => @model, "output" => [] }
      else
        flunk("Unexpected create call ##{create_count}")
      end
    end

    completed_calls = []
    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**_kwargs| true }
    fake_run_log.define_singleton_method(:record_completed) { |**kwargs| completed_calls << kwargs }
    fake_run_log.define_singleton_method(:record_failed) { |**_kwargs| nil }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          access_token: @access_token,
          base_uri: supported_apis(:openai).api_base_uri,
          model: @model,
          log_completion: false,
          agent_run: true
        )

        first_submission = service.complete(
          [ { role: "user", content: "Run long task" } ],
          background: true,
          metadata: { run_id: "run_aggregate", run_type: "propose_resources" }
        )
        assert_equal "resp_turn_1", first_submission["id"]
        service.wait_for_response("resp_turn_1", timeout_seconds: 5, poll_interval_seconds: 0)
        assert_equal 0, completed_calls.size

        second_submission = service.complete(
          nil,
          input: [ { "type" => "function_call_output", "call_id" => "call_1", "output" => "{}" } ],
          background: true,
          previous_response_id: "resp_turn_1",
          metadata: { run_type: "propose_resources" }
        )
        assert_equal "resp_turn_2", second_submission["id"]
        service.wait_for_response("resp_turn_2", timeout_seconds: 5, poll_interval_seconds: 0)
      end
    end

    assert_equal 1, completed_calls.size
    assert_equal "run_aggregate", completed_calls.first[:run_id]
    assert_equal "resp_turn_2", completed_calls.first[:response_id]
    assert_equal(
      { assistant_turns: 1, tool_call_count: 1, tool_turn_count: 1, reasoning_item_count: 0, output_item_count: 2 },
      completed_calls.first[:metrics]
    )
    assert_equal 1, completed_calls.first[:tool_calls].size
    logged_call = completed_calls.first[:tool_calls].first
    assert_equal "resp_turn_1", logged_call[:response_id]
    assert_equal "call_1", logged_call[:call_id]
    assert_equal "exa_search", logged_call[:name]
    assert logged_call[:arguments_preview].present?
    assert_equal 64, logged_call[:argument_fingerprint].to_s.length
  end

  test "wait_for_response does not mark run completed when response only contains tool calls" do
    fake_client = build_responses_client(
      retrieve_proc: lambda { |_response_id, _params|
        {
          "id" => "resp_bg",
          "status" => "completed",
          "output" => [
            { "type" => "function_call", "call_id" => "call_1", "name" => "lookup", "arguments" => "{}" }
          ]
        }
      }
    ) do |_params|
      {
        "id" => "resp_bg",
        "status" => "queued",
        "model" => @model,
        "output" => []
      }
    end

    submitted_calls = []
    completed_calls = []
    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**kwargs| submitted_calls << kwargs }
    fake_run_log.define_singleton_method(:record_completed) { |**kwargs| completed_calls << kwargs }
    fake_run_log.define_singleton_method(:record_failed) { |**_kwargs| nil }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          access_token: @access_token,
          base_uri: supported_apis(:openai).api_base_uri,
          model: @model,
          log_completion: false,
          agent_run: true
        )

        service.complete(
          [ { role: "user", content: "Run long task" } ],
          background: true,
          metadata: { run_id: "run_2", run_type: "delegate_to_frontier_llm" }
        )
        result = service.wait_for_response("resp_bg", timeout_seconds: 5, poll_interval_seconds: 0)
        assert_equal "completed", result["status"]
      end
    end

    assert_equal 1, submitted_calls.size
    assert_equal 0, completed_calls.size
  end

  test "mark_current_agent_run_failed logs aggregate metrics after tool-call turn completes" do
    fake_client = build_responses_client(
      retrieve_proc: lambda { |_response_id, _params|
        {
          "id" => "resp_bg",
          "status" => "completed",
          "output" => [
            { "type" => "function_call", "call_id" => "call_1", "name" => "lookup", "arguments" => "{\"query\":\"oak\"}" }
          ]
        }
      }
    ) do |_params|
      {
        "id" => "resp_bg",
        "status" => "queued",
        "model" => @model,
        "output" => []
      }
    end

    failed_calls = []
    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**_kwargs| true }
    fake_run_log.define_singleton_method(:record_completed) { |**_kwargs| nil }
    fake_run_log.define_singleton_method(:record_failed) { |**kwargs| failed_calls << kwargs }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          access_token: @access_token,
          base_uri: supported_apis(:openai).api_base_uri,
          model: @model,
          log_completion: false,
          agent_run: true
        )

        service.complete(
          [ { role: "user", content: "Run long task" } ],
          background: true,
          metadata: { run_id: "run_failed", run_type: "propose_resources" }
        )
        response_hash = service.wait_for_response("resp_bg", timeout_seconds: 5, poll_interval_seconds: 0)
        service.mark_current_agent_run_failed(
          error_message: "Tool-call limit exceeded (1). Ask the user to confirm how to proceed.",
          response_hash: response_hash
        )
      end
    end

    assert_equal 1, failed_calls.size
    assert_equal "run_failed", failed_calls.first[:run_id]
    assert_equal "resp_bg", failed_calls.first[:response_id]
    assert_equal(
      { assistant_turns: 0, tool_call_count: 1, tool_turn_count: 1, reasoning_item_count: 0, output_item_count: 1 },
      failed_calls.first[:metrics]
    )
    assert_equal 1, failed_calls.first[:tool_calls].size
    assert_equal "call_1", failed_calls.first[:tool_calls].first[:call_id]
    assert_equal "lookup", failed_calls.first[:tool_calls].first[:name]
  end

  test "background calls with a conversation do not log agent runs" do
    fake_client = build_responses_client do |_params|
      { "id" => "resp_bg", "status" => "queued", "model" => @model, "output" => [] }
    end

    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**_kwargs| flunk("record_submitted should not be called") }
    fake_run_log.define_singleton_method(:record_completed) { |**_kwargs| flunk("record_completed should not be called") }
    fake_run_log.define_singleton_method(:record_failed) { |**_kwargs| flunk("record_failed should not be called") }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        service = OpenaiResponsesService.new(
          current_user: @user,
          conversation: @conversation,
          access_token: @access_token,
          base_uri: @base_uri,
          model: @model,
          log_completion: false
        )

        result = service.complete(
          [ { role: "user", content: "Run long task" } ],
          background: true,
          metadata: { run_id: "run_3", run_type: "chat_background" }
        )
        assert_equal "resp_bg", result["id"]
      end
    end
  end

  test "background run logs overview and tool call sequence without payload dump" do
    fake_client = build_responses_client(
      retrieve_proc: lambda { |_response_id, _params|
        response_payload("Done", id: "resp_bg").merge("status" => "completed")
      }
    ) do |_params|
      {
        "id" => "resp_bg",
        "status" => "queued",
        "model" => @model,
        "output" => [
          { "type" => "function_call", "call_id" => "call_1", "name" => "exa_search", "arguments" => "{\"query\":\"refraction\"}" }
        ]
      }
    end

    fake_run_log = Object.new
    fake_run_log.define_singleton_method(:record_submitted) { |**_kwargs| true }
    fake_run_log.define_singleton_method(:record_completed) { |**_kwargs| true }
    fake_run_log.define_singleton_method(:record_failed) { |**_kwargs| true }

    info_logs = []
    debug_logs = []
    error_logs = []
    fake_logger = Object.new
    fake_logger.define_singleton_method(:debug?) { true }
    fake_logger.define_singleton_method(:info) { |message| info_logs << message }
    fake_logger.define_singleton_method(:debug) { |message| debug_logs << message }
    fake_logger.define_singleton_method(:error) { |message| error_logs << message }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        Rails.stub(:logger, fake_logger) do
          service = OpenaiResponsesService.new(
            current_user: @user,
            access_token: @access_token,
            base_uri: supported_apis(:openai).api_base_uri,
            model: @model,
            log_completion: false,
            agent_run: true
          )

          service.complete(
            [ { role: "user", content: "Run long task" } ],
            background: true,
            metadata: { run_id: "run_log_1", run_type: "propose_resources", source: "propose_resources" }
          )
          service.wait_for_response("resp_bg", timeout_seconds: 5, poll_interval_seconds: 0)
        end
      end
    end

    assert info_logs.any? { |msg| msg.include?("Responses run overview phase=submit") && msg.include?("tool_calls=exa_search(call_1)") }
    assert info_logs.any? { |msg| msg.include?("Responses run tool call sequence run_id=run_log_1") }
    assert debug_logs.none? { |msg| msg.include?("Responses API response:") }
    assert error_logs.none?
  end

  test "development logs full response payloads" do
    fake_client = build_responses_client do |_params|
      response_payload("Done", id: "resp_dev_log")
    end

    info_logs = []
    debug_logs = []
    warn_logs = []
    error_logs = []
    fake_logger = Object.new
    fake_logger.define_singleton_method(:debug?) { true }
    fake_logger.define_singleton_method(:info) { |message| info_logs << message }
    fake_logger.define_singleton_method(:debug) { |message| debug_logs << message }
    fake_logger.define_singleton_method(:warn) { |message| warn_logs << message }
    fake_logger.define_singleton_method(:error) { |message| error_logs << message }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      Rails.env.stub(:development?, true) do
        Rails.stub(:logger, fake_logger) do
          service = OpenaiResponsesService.new(
            current_user: @user,
            conversation: @conversation,
            access_token: @access_token,
            base_uri: @base_uri,
            model: @model,
            log_completion: false
          )

          assert_equal "Done", service.complete([ { role: "user", content: "Hello" } ])
        end
      end
    end

    assert info_logs.any? { |message|
      message.include?("Responses API response phase=submit") &&
        message.include?("resp_dev_log") &&
        message.include?(%("output"))
    }
    assert warn_logs.none?
    assert error_logs.none?
  end

  test "development logs API exception response details" do
    error_class = Class.new(StandardError) do
      def response
        { status: 502, body: "unexpected end of input at line 178 column 1" }
      end
    end

    fake_client = build_responses_client do |_params|
      raise error_class, "unexpected end of input at line 178 column 1"
    end

    info_logs = []
    debug_logs = []
    warn_logs = []
    error_logs = []
    fake_logger = Object.new
    fake_logger.define_singleton_method(:debug?) { true }
    fake_logger.define_singleton_method(:info) { |message| info_logs << message }
    fake_logger.define_singleton_method(:debug) { |message| debug_logs << message }
    fake_logger.define_singleton_method(:warn) { |message| warn_logs << message }
    fake_logger.define_singleton_method(:error) { |message| error_logs << message }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      Rails.env.stub(:development?, true) do
        Rails.stub(:logger, fake_logger) do
          service = OpenaiResponsesService.new(
            current_user: @user,
            conversation: @conversation,
            access_token: @access_token,
            base_uri: @base_uri,
            model: @model,
            log_completion: false
          )

          error = assert_raises(OpenAiError) do
            service.complete([ { role: "user", content: "Hello" } ])
          end
          assert_includes error.message, "unexpected end of input"
        end
      end
    end

    assert error_logs.any? { |message|
      message.include?("Responses API exception") &&
        message.include?("502") &&
        message.include?("unexpected end of input")
    }
    assert warn_logs.none?
    assert info_logs.none? { |message| message.include?("Responses API response phase=submit") }
  end

  test "log_request_input_items skips payload serialization when debug logging is disabled" do
    fake_client = build_responses_client do |_params|
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      pretty_generate_called = false
      Rails.logger.stub(:debug?, false) do
        JSON.stub(:pretty_generate, lambda { |_item|
          pretty_generate_called = true
          "{}"
        }) do
          result = service.send(:log_request_input_items, [ { "role" => "user", "content" => "Hello" } ])
          assert_nil result
        end
      end
      assert_equal false, pretty_generate_called
    end
  end

  private

  def create_openrouter_supported_api
    SupportedApi.create!(
      api_base_uri: SupportedApi::OPENROUTER_BASE_URI,
      api_access_token: "openrouter-test-token",
      enabled: true
    )
  end

  def build_responses_client(retrieve_proc: nil, &create_proc)
    responses = Object.new
    responses.define_singleton_method(:create) do |**params|
      create_proc.call(params)
    end
    if retrieve_proc
      responses.define_singleton_method(:retrieve) do |response_id, **params|
        retrieve_proc.call(response_id, params)
      end
    end

    client = Object.new
    client.define_singleton_method(:responses) { responses }
    client
  end

  def response_payload(text, id: "resp_1")
    {
      "id" => id,
      "model" => @model,
      "output" => [
        {
          "type" => "message",
          "content" => [
            { "type" => "output_text", "text" => text }
          ]
        }
      ],
      "usage" => {}
    }
  end

  def codex_completed_stream(response)
    lambda do |_request_params, _request_options_param|
      [
        { "type" => "response.completed", "response" => response }
      ].to_enum
    end
  end
end
