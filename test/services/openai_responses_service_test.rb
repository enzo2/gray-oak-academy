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

    assert_equal "Custom system prompt", captured[:instructions]
    assert_equal "user", captured[:input][0]["role"]
    assert_equal "Find answer", captured[:input][0]["content"]
    assert_equal "function_call", captured[:input][1]["type"]
    assert_equal "call_1", captured[:input][1]["call_id"]
    assert_equal "Lookup", captured[:input][1]["name"]
    assert_equal "function_call_output", captured[:input][2]["type"]
    assert_equal "call_1", captured[:input][2]["call_id"]
    assert_equal "tool output", captured[:input][2]["output"]
  end

  test "complete with store false does not write response state to conversation" do
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
        base_uri: @base_uri,
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
          base_uri: @base_uri,
          model: @model,
          log_completion: false
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
    assert_equal "propose_resources", submitted_calls.first[:source]
    assert_equal "Preview task", submitted_calls.first[:prompt]

    assert_equal 1, completed_calls.size
    assert_equal "run_1", completed_calls.first[:run_id]
    assert_equal "resp_bg", completed_calls.first[:response_id]
    assert_equal 0, failed_calls.size
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
          base_uri: @base_uri,
          model: @model,
          log_completion: false
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
          base_uri: @base_uri,
          model: @model,
          log_completion: false
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
    fake_logger.define_singleton_method(:info) { |message| info_logs << message }
    fake_logger.define_singleton_method(:debug) { |message| debug_logs << message }
    fake_logger.define_singleton_method(:error) { |message| error_logs << message }

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      AgentRunLogService.stub(:new, ->(**_kwargs) { fake_run_log }) do
        Rails.stub(:logger, fake_logger) do
          service = OpenaiResponsesService.new(
            current_user: @user,
            access_token: @access_token,
            base_uri: @base_uri,
            model: @model,
            log_completion: false
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
