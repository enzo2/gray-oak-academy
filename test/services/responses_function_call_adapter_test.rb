require "test_helper"
require "ostruct"

class ResponsesFunctionCallAdapterTest < ActiveSupport::TestCase
  test "delegate provider-native tools uses web_search fallback when Exa is disabled" do
    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      exa_enabled: false,
      allow_app_tools: false
    )

    assert_equal [ { type: "web_search" } ], adapter.delegate_provider_native_tools
    assert_equal [], adapter.delegate_flow_tools
  end

  test "delegate flow tools expose Exa function tools when enabled" do
    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      exa_enabled: true,
      allow_app_tools: false
    )

    assert_equal [], adapter.delegate_provider_native_tools
    names = adapter.delegate_flow_tools.map { |tool| tool[:name] }
    assert_includes names, "exa_websearch"
    assert_includes names, "exa_answer"
  end

  test "function calls ignores malformed blank-name response artifacts" do
    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      exa_enabled: true,
      allow_app_tools: false
    )

    response_hash = {
      "id" => "resp_openrouter",
      "output" => [
        { "type" => "function_call", "name" => "exa_websearch", "call_id" => "call_valid", "arguments" => { query: "refraction demo" }.to_json },
        { "type" => "function_call", "name" => "", "call_id" => "chatcmpl-tool-empty", "arguments" => "{}" },
        { "type" => "function_call", "name" => "exa_answer", "call_id" => "", "arguments" => "{}" },
        { "type" => "message", "content" => [ { "type" => "output_text", "text" => "done" } ] }
      ]
    }

    calls = adapter.function_calls(response_hash)

    assert_equal [ "call_valid" ], calls.map { |call| call["call_id"] }
    assert_equal [ "exa_websearch" ], calls.map { |call| call["name"] }
  end

  test "executes exa function call and returns function_call_output" do
    captured = {}
    fake_exa = Object.new
    fake_exa.define_singleton_method(:search) do |**kwargs|
      captured[:kwargs] = kwargs
      { "query" => kwargs[:query], "results" => [ { "url" => "https://example.com" } ] }
    end

    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      exa_enabled: true,
      allow_app_tools: false
    )

    ExaApiService.stub(:new, ->(**_kwargs) { fake_exa }) do
      outputs = adapter.function_call_outputs([
        {
          "type" => "function_call",
          "name" => "exa_websearch",
          "call_id" => "call_exa_1",
          "arguments" => { query: "refraction demo" }.to_json
        }
      ])

      assert_equal "function_call_output", outputs.first[:type]
      assert_equal "call_exa_1", outputs.first[:call_id]
      assert_includes outputs.first[:output], "https://example.com"
      assert_includes outputs.first[:output], "refraction demo"
      assert_equal 10, captured.dig(:kwargs, :numResults)
      assert_equal false, captured.dig(:kwargs, :contents, :text)
      assert_equal 2000, captured.dig(:kwargs, :contents, :highlights, :maxCharacters)
      assert_nil captured.dig(:kwargs, :highlights)
    end
  end

  test "executes app tool calls through tool execution service" do
    conversation = conversations(:teacher_generic_conversation)
    fake_executor = Object.new
    fake_executor.define_singleton_method(:execute_tool_call) do |_tool_call|
      OpenStruct.new(content: "Tool ran successfully")
    end

    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      conversation: conversation,
      exa_enabled: false
    )

    ToolExecutionService.stub(:new, ->(**_kwargs) { fake_executor }) do
      outputs = adapter.function_call_outputs([
        {
          "type" => "function_call",
          "name" => "list_courses",
          "call_id" => "call_app_1",
          "arguments" => {}.to_json
        }
      ])

      assert_equal "function_call_output", outputs.first[:type]
      assert_equal "call_app_1", outputs.first[:call_id]
      assert_equal "Tool ran successfully", outputs.first[:output]
    end
  end

  test "falls back to persisted tool message when app tool returns non-message value" do
    conversation = conversations(:teacher_generic_conversation)
    call_id = "call_app_true"
    Message.create!(
      conversation: conversation,
      role: "tool",
      content: GenerateImageJob::SUCCESS_MESSAGE,
      tool_call_id: call_id
    )

    fake_executor = Object.new
    fake_executor.define_singleton_method(:execute_tool_call) do |_tool_call|
      true
    end

    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      conversation: conversation,
      exa_enabled: false
    )

    ToolExecutionService.stub(:new, ->(**_kwargs) { fake_executor }) do
      outputs = adapter.function_call_outputs([
        {
          "type" => "function_call",
          "name" => "generate_image",
          "call_id" => call_id,
          "arguments" => { prompt: "water cycle infographic" }.to_json
        }
      ])

      assert_equal "function_call_output", outputs.first[:type]
      assert_equal call_id, outputs.first[:call_id]
      assert_equal GenerateImageJob::SUCCESS_MESSAGE, outputs.first[:output]
    end
  end

  test "returns generated image tool results as Responses image content when model supports image input" do
    conversation = conversations(:teacher_generic_conversation)
    conversation.define_singleton_method(:image_input_supported?) { true }
    call_id = "call_image_visible"
    tool_message = Message.create!(
      conversation: conversation,
      role: "tool",
      content: GenerateImageJob::SUCCESS_MESSAGE,
      tool_call_id: call_id
    )
    tool_message.images.create!(
      uri: "https://example.com/generated.png",
      content_type: "image/png"
    )

    fake_executor = Object.new
    fake_executor.define_singleton_method(:execute_tool_call) do |_tool_call|
      true
    end

    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      conversation: conversation,
      exa_enabled: false
    )

    ToolExecutionService.stub(:new, ->(**_kwargs) { fake_executor }) do
      outputs = adapter.function_call_outputs([
        {
          "type" => "function_call",
          "name" => "generate_image",
          "call_id" => call_id,
          "arguments" => { prompt: "water cycle infographic" }.to_json
        }
      ])

      output = outputs.first[:output]
      assert_equal "function_call_output", outputs.first[:type]
      assert_equal call_id, outputs.first[:call_id]
      assert_instance_of Array, output
      assert_equal "input_text", output.first["type"]
      assert_equal GenerateImageJob::SUCCESS_MESSAGE, output.first["text"]
      assert_equal "input_image", output.second["type"]
      assert_equal "https://example.com/generated.png", output.second["image_url"]
      assert_equal "auto", output.second["detail"]
    end
  end

  test "returns text-only generated image result when model does not support image input" do
    conversation = conversations(:teacher_generic_conversation)
    conversation.define_singleton_method(:image_input_supported?) { false }
    call_id = "call_image_text_only"
    tool_message = Message.create!(
      conversation: conversation,
      role: "tool",
      content: GenerateImageJob::SUCCESS_MESSAGE,
      tool_call_id: call_id
    )
    tool_message.images.create!(
      uri: "https://example.com/generated.png",
      content_type: "image/png"
    )

    fake_executor = Object.new
    fake_executor.define_singleton_method(:execute_tool_call) do |_tool_call|
      true
    end

    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      conversation: conversation,
      exa_enabled: false
    )

    ToolExecutionService.stub(:new, ->(**_kwargs) { fake_executor }) do
      outputs = adapter.function_call_outputs([
        {
          "type" => "function_call",
          "name" => "generate_image",
          "call_id" => call_id,
          "arguments" => { prompt: "water cycle infographic" }.to_json
        }
      ])

      output = outputs.first[:output]
      assert_instance_of String, output
      assert_includes output, GenerateImageJob::SUCCESS_MESSAGE
      assert_includes output, "does not support image input"
    end
  end
end
