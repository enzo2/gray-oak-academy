require "test_helper"
require "ostruct"

class ResponsesFunctionCallAdapterTest < ActiveSupport::TestCase
  test "delegate native tools uses web_search fallback when Exa is disabled" do
    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      exa_enabled: false,
      allow_app_tools: false
    )

    assert_equal [ { type: "web_search" } ], adapter.delegate_native_tools
  end

  test "delegate native tools exposes Exa function tools when enabled" do
    adapter = ResponsesFunctionCallAdapter.new(
      current_user: users(:admin),
      exa_enabled: true,
      allow_app_tools: false
    )

    names = adapter.delegate_native_tools.map { |tool| tool[:name] }
    assert_includes names, "exa_websearch"
    assert_includes names, "exa_answer"
  end

  test "executes exa function call and returns function_call_output" do
    fake_exa = Object.new
    fake_exa.define_singleton_method(:search) do |**kwargs|
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
end
