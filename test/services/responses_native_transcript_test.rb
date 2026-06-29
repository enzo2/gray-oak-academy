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

  test "accepts content-array reasoning and rejects summary-only reasoning" do
    transcript = ResponsesNativeTranscript.new(initial_input_items: [ { role: "user", content: "test" } ])
    # OpenRouter's normalized Responses shape for non-encrypted reasoning (e.g. minimax):
    # the reasoning text lives under a `content` array of `reasoning_text` items.
    content_reasoning = {
      "output" => [
        { "type" => "reasoning", "format" => "unknown",
          "content" => [ { "type" => "reasoning_text", "text" => "provider reasoning" } ] },
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

    assert transcript.reasoning_replayable_for_tool_boundary?(content_reasoning)
    refute transcript.reasoning_replayable_for_tool_boundary?(summary_only)
  end

  test "rejects partial parallel tool output sets" do
    transcript = ResponsesNativeTranscript.new(initial_input_items: [ { role: "user", content: "test" } ])
    transcript.append_response!({
      "output" => [
        { "type" => "function_call", "call_id" => "call_1", "name" => "first", "arguments" => "{}" },
        { "type" => "function_call", "call_id" => "call_2", "name" => "second", "arguments" => "{}" }
      ]
    })

    error = assert_raises(OpenAiError) do
      transcript.append_function_call_outputs!([
        { type: "function_call_output", call_id: "call_1", output: "one" }
      ])
    end
    assert_includes error.message, "missing=call_2"
  end

  test "drops malformed function calls before stateless replay" do
    initial = [
      { "role" => "developer", "content" => "system" },
      { "role" => "user", "content" => "research" }
    ]
    response = {
      "id" => "resp_openrouter",
      "output" => [
        { "type" => "function_call", "call_id" => "call_valid", "name" => "exa_search", "arguments" => "{}" },
        { "type" => "function_call", "call_id" => "chatcmpl-tool-empty", "name" => "", "arguments" => "{}" },
        { "type" => "function_call", "call_id" => "", "name" => "fetch_image", "arguments" => "{}" }
      ]
    }
    transcript = ResponsesNativeTranscript.new(initial_input_items: initial)

    transcript.append_response!(response)
    transcript.append_function_call_outputs!([
      { type: "function_call_output", call_id: "call_valid", output: "ok" }
    ])

    replay = transcript.input_items
    replayed_calls = replay.select { |item| item["type"] == "function_call" }
    assert_equal 1, replayed_calls.size
    assert_equal "call_valid", replayed_calls.first["call_id"]
    assert_equal "exa_search", replayed_calls.first["name"]
    assert_equal "call_valid", replay.last[:call_id]
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
