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
      content: "Image generation done.",
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
      assert_equal "Image generation done.", outputs.first[:output]
    end
  end
end
