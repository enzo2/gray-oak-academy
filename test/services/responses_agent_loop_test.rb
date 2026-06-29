require "test_helper"

class ResponsesAgentLoopTest < ActiveSupport::TestCase
  test "resends resolved input with verbatim output and complete parallel tool results" do
    responses = [
      {
        "id" => "resp_1",
        "status" => "completed",
        "usage" => { "input_tokens" => 20 },
        "output" => [
          { "type" => "reasoning", "format" => "unknown", "signature" => "keep-exactly", "custom" => "field" },
          { "type" => "function_call", "id" => "fc_1", "call_id" => "call_1", "name" => "first", "arguments" => "{}" },
          { "type" => "function_call", "id" => "fc_2", "call_id" => "call_2", "name" => "second", "arguments" => "{}" }
        ]
      },
      {
        "id" => "resp_2",
        "status" => "completed",
        "usage" => { "input_tokens" => 40 },
        "output" => [
          { "type" => "reasoning", "signature" => "second-signature", "format" => "anthropic" },
          { "type" => "function_call", "id" => "fc_3", "call_id" => "call_3", "name" => "third", "arguments" => "{}" }
        ]
      },
      {
        "id" => "resp_3",
        "status" => "completed",
        "usage" => { "input_tokens" => 60 },
        "output" => [ { "type" => "message", "content" => [ { "type" => "output_text", "text" => "done" } ] } ]
      }
    ]
    client, calls = fake_client(responses)
    loop = ResponsesAgentLoop.new(client: client)

    first = loop.start(messages: [ { role: "user", content: "start" } ], metadata: { run_id: "run_1" })
    assert_equal "resp_1", first["id"]
    second = loop.continue_with_tool_outputs(
      outputs: [
        { type: "function_call_output", call_id: "call_2", output: "two" },
        { type: "function_call_output", call_id: "call_1", output: "one" }
      ],
      metadata: { run_id: "run_1", phase: "tool_turn" }
    )

    assert_equal "resp_2", second["id"]
    replay = calls.second.dig(:kwargs, :input)
    assert_equal [ "developer", "user" ], replay.first(2).map { |item| item["role"] }
    assert_equal responses.first["output"], replay[2, 3]
    assert_equal [ "call_1", "call_2" ], replay.last(2).map { |item| item[:call_id] }

    final = loop.continue_with_tool_outputs(
      outputs: [ { type: "function_call_output", call_id: "call_3", output: "three" } ],
      metadata: { run_id: "run_1", phase: "tool_turn" }
    )

    assert_equal "resp_3", final["id"]
    second_replay = calls.third.dig(:kwargs, :input)
    assert_equal responses.second["output"], second_replay[7, 2]
    assert_equal "call_3", second_replay.last[:call_id]
    assert calls.all? { |call| call.dig(:kwargs, :request_timeout_seconds).present? }
  end

  test "restarts first tool turn with reasoning disabled before returning it" do
    responses = [
      {
        "id" => "resp_summary_only",
        "status" => "completed",
        "usage" => { "output_tokens_details" => { "reasoning_tokens" => 12 } },
        "output" => [
          { "type" => "reasoning", "summary" => [ { "text" => "not replayable" } ] },
          { "type" => "function_call", "call_id" => "call_unsafe", "name" => "mutate", "arguments" => "{}" }
        ]
      },
      {
        "id" => "resp_no_reasoning",
        "status" => "completed",
        "usage" => { "output_tokens_details" => { "reasoning_tokens" => 4 } },
        "output" => [
          { "type" => "reasoning", "summary" => [ { "text" => "provider ignored none" } ] },
          { "type" => "function_call", "call_id" => "call_safe", "name" => "mutate", "arguments" => "{}" }
        ]
      },
      {
        "id" => "resp_done",
        "status" => "completed",
        "output" => [ { "type" => "message", "content" => [ { "type" => "output_text", "text" => "done" } ] } ]
      }
    ]
    client, calls = fake_client(responses)
    loop = ResponsesAgentLoop.new(client: client)

    response = loop.start(messages: [ { role: "user", content: "start" } ], metadata: { run_id: "run_fallback" })

    assert_equal "resp_no_reasoning", response["id"]
    assert loop.reasoning_fallback_used
    assert_equal({ effort: "high" }, calls.first.dig(:kwargs, :reasoning))
    assert_equal({ effort: "none" }, calls.second.dig(:kwargs, :reasoning))
    assert_equal "reasoning_fallback", calls.second.dig(:kwargs, :metadata, :phase)

    final = loop.continue_with_tool_outputs(
      outputs: [ { type: "function_call_output", call_id: "call_safe", output: "ok" } ],
      metadata: { run_id: "run_fallback", phase: "tool_turn" }
    )
    assert_equal "resp_done", final["id"]
    replay_types = calls.third.dig(:kwargs, :input).map { |item| item["type"] || item[:type] }
    refute_includes replay_types, "reasoning"
  end

  test "does not replay malformed OpenRouter function-call artifacts" do
    responses = [
      {
        "id" => "resp_1",
        "status" => "completed",
        "usage" => { "input_tokens" => 20 },
        "output" => [
          { "type" => "function_call", "call_id" => "call_valid", "name" => "exa_search", "arguments" => "{}" },
          { "type" => "function_call", "call_id" => "chatcmpl-tool-empty", "name" => "", "arguments" => "{}" }
        ]
      },
      {
        "id" => "resp_2",
        "status" => "completed",
        "output" => [ { "type" => "message", "content" => [ { "type" => "output_text", "text" => "done" } ] } ]
      }
    ]
    client, calls = fake_client(responses)
    loop = ResponsesAgentLoop.new(client: client)

    loop.start(messages: [ { role: "user", content: "start" } ], metadata: { run_id: "run_openrouter" })
    loop.continue_with_tool_outputs(
      outputs: [ { type: "function_call_output", call_id: "call_valid", output: "ok" } ],
      metadata: { run_id: "run_openrouter", phase: "tool_turn" }
    )

    replay = calls.second.dig(:kwargs, :input)
    replayed_calls = replay.select { |item| item["type"] == "function_call" }
    assert_equal [ "call_valid" ], replayed_calls.map { |item| item["call_id"] }
    refute replayed_calls.any? { |item| item["name"].blank? }
  end

  test "stops a continuation at eighty percent of known context" do
    model = "context-guard-model"
    Llm.create!(api_provider: SupportedApi::OPENROUTER_BASE_URI, model: model, context_length: 100)
    response = {
      "id" => "resp_context",
      "status" => "completed",
      "usage" => { "input_tokens" => 80 },
      "output" => [ { "type" => "function_call", "call_id" => "call_1", "name" => "lookup", "arguments" => "{}" } ]
    }
    client, = fake_client([ response ], model: model)
    loop = ResponsesAgentLoop.new(client: client)
    loop.start(messages: [ { role: "user", content: "start" } ], metadata: { run_id: "run_context" })

    error = assert_raises(OpenAiError) do
      loop.continue_with_tool_outputs(
        outputs: [ { type: "function_call_output", call_id: "call_1", output: "ok" } ],
        metadata: { run_id: "run_context" }
      )
    end
    assert_includes error.message, "context safety limit"
  end

  private

  def fake_client(responses, model: "agent-test-model")
    calls = []
    client = Object.new
    client.define_singleton_method(:model) { model }
    client.define_singleton_method(:base_uri) { SupportedApi::OPENROUTER_BASE_URI }
    client.define_singleton_method(:last_input_items) { @last_input_items.deep_dup }
    client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      calls << { messages: messages, kwargs: kwargs }
      @last_input_items = if messages.present?
        [
          { "role" => "developer", "content" => "system" },
          { "role" => "user", "content" => messages.first[:content] }
        ]
      else
        kwargs.fetch(:input).deep_dup
      end
      { "id" => responses.fetch(calls.size - 1)["id"] }
    end
    client.define_singleton_method(:wait_for_response) do |response_id, **_kwargs|
      responses.find { |response| response["id"] == response_id }
    end
    [ client, calls ]
  end
end
