require "test_helper"

class OpenaiResponsesServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @conversation = conversations(:teacher_generic_conversation)
    @base_uri = "https://api.test/"
    @access_token = "tok"
    @model = "m1"
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
      openai_agent_supported_api_id: supported_apis(:xai).id,
      openai_agent_model: "grok-4-0709"
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

  test "agent_run mode rejects unsupported provider overrides" do
    AppSetting.first.update!(openai_agent_model: "gpt-5.2")

    error = assert_raises(OpenAiError) do
      OpenaiResponsesService.new(
        current_user: @user,
        base_uri: supported_apis(:example_api).api_base_uri,
        agent_run: true,
        log_completion: false
      )
    end

    assert_includes error.message, "Background agent runs provider is not configured"
  end

  test "stateful provider helper accepts openai and xai hosts only" do
    assert OpenaiResponsesService.stateful_supported_base_uri?("https://api.openai.com/v1/")
    assert OpenaiResponsesService.stateful_supported_base_uri?("https://api.x.ai/v1/")
    refute OpenaiResponsesService.stateful_supported_base_uri?("https://api.example.com/v1/")
    refute OpenaiResponsesService.stateful_supported_base_uri?("https://openrouter.ai/api/v1/")
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
end
