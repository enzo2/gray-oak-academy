require "test_helper"

class ResponsesNativeTranscriptTest < ActiveSupport::TestCase
  test "replays response items verbatim and appends every parallel output in call order" do
    initial = [
      { "role" => "developer", "content" => "system" },
      { "role" => "user", "content" => "research" }
    ]
    response = {
      "output" => [
        {
          "type" => "reasoning",
          "id" => "reasoning_1",
          "format" => "anthropic-claude-v1",
          "signature" => "opaque-signature",
          "provider_extension" => { "untouched" => true }
        },
        { "type" => "function_call", "id" => "fc_1", "call_id" => "call_1", "name" => "first", "arguments" => "{}" },
        { "type" => "function_call", "id" => "fc_2", "call_id" => "call_2", "name" => "second", "arguments" => "{}" }
      ]
    }
    transcript = ResponsesNativeTranscript.new(initial_input_items: initial)

    assert transcript.reasoning_replayable_for_tool_boundary?(response)
    transcript.append_response!(response)
    transcript.append_function_call_outputs!([
      { type: "function_call_output", call_id: "call_2", output: "two" },
      { type: "function_call_output", call_id: "call_1", output: "one" }
    ])

    replay = transcript.input_items
    assert_equal initial, replay.first(2)
    assert_equal response["output"], replay[2, 3]
    assert_equal [ "call_1", "call_2" ], replay.last(2).map { |item| item[:call_id] }
    replay.first["content"] = "mutated"
    assert_equal "system", transcript.input_items.first["content"]
  end

  test "accepts Kimi content reasoning and rejects summary-only reasoning" do
    transcript = ResponsesNativeTranscript.new(initial_input_items: [ { role: "user", content: "test" } ])
    kimi = {
      "output" => [
        { "type" => "reasoning", "format" => "unknown", "content" => "provider reasoning" },
        { "type" => "function_call", "call_id" => "call_1", "name" => "lookup", "arguments" => "{}" }
      ]
    }
    summary_only = {
      "usage" => { "output_tokens_details" => { "reasoning_tokens" => 10 } },
      "output" => [
        { "type" => "reasoning", "summary" => [ { "text" => "summary" } ] },
        { "type" => "function_call", "call_id" => "call_1", "name" => "lookup", "arguments" => "{}" }
      ]
    }

    assert transcript.reasoning_replayable_for_tool_boundary?(kimi)
    refute transcript.reasoning_replayable_for_tool_boundary?(summary_only)
  end

  test "rejects partial parallel tool output sets" do
    transcript = ResponsesNativeTranscript.new(initial_input_items: [ { role: "user", content: "test" } ])
    transcript.append_response!({
      "output" => [
        { "type" => "function_call", "call_id" => "call_1" },
        { "type" => "function_call", "call_id" => "call_2" }
      ]
    })

    error = assert_raises(OpenAiError) do
      transcript.append_function_call_outputs!([
        { type: "function_call_output", call_id: "call_1", output: "one" }
      ])
    end
    assert_includes error.message, "missing=call_2"
  end

  test "can omit unreplayable reasoning only for the disabled-reasoning fallback" do
    transcript = ResponsesNativeTranscript.new(initial_input_items: [ { role: "user", content: "test" } ])
    response = {
      "output" => [
        { "type" => "reasoning", "summary" => [ { "text" => "summary only" } ] },
        { "type" => "function_call", "call_id" => "call_1", "name" => "lookup", "arguments" => "{}" }
      ]
    }

    refute transcript.reasoning_replayable_for_tool_boundary?(response)
    transcript.append_response!(response, omit_reasoning: true)

    assert_equal [ "function_call" ], transcript.input_items.filter_map { |item| item["type"] }
  end
end
