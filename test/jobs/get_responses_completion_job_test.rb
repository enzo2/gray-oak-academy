require "test_helper"

class GetResponsesCompletionJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  test "loops through function calls and persists assistant messages" do
    conversation = conversations(:teacher_generic_conversation)
    conversation.messages.delete_all
    conversation.messages.create!(role: :user, content: "Please help")

    fake_client = Object.new
    calls = []
    response_index = 0
    responses = [
      {
        "id" => "resp_1",
        "status" => "completed",
        "output" => [
          {
            "type" => "function_call",
            "name" => "list_courses",
            "call_id" => "call_1",
            "arguments" => {}.to_json
          }
        ]
      },
      {
        "id" => "resp_2",
        "status" => "completed",
        "output" => [
          { "type" => "message", "content" => [ { "type" => "output_text", "text" => "Final assistant reply" } ] }
        ]
      }
    ]

    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      calls << { messages: messages, kwargs: kwargs }
      response_index += 1
    end
    fake_client.define_singleton_method(:last_response_hash) do
      responses[response_index - 1]
    end
    fake_client.define_singleton_method(:output_text) do |response_hash|
      if response_hash["id"] == "resp_2"
        "Final assistant reply"
      else
        ""
      end
    end

    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:conversation_flow_tools) { [] }
    fake_adapter.define_singleton_method(:function_calls) do |response_hash|
      Array(response_hash["output"]).select { |item| item["type"] == "function_call" }
    end
    fake_adapter.define_singleton_method(:function_call_outputs) do |_calls|
      [ { type: "function_call_output", call_id: "call_1", output: "tool output" } ]
    end
    fake_adapter.define_singleton_method(:function_calls_as_chat_tool_calls) do |calls_for_message|
      calls_for_message.map do |call|
        {
          "type" => "function",
          "id" => call["call_id"],
          "function" => { "name" => call["name"], "arguments" => call["arguments"] }
        }
      end
    end

    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_client }) do
      ResponsesFunctionCallAdapter.stub(:new, ->(**_kwargs) { fake_adapter }) do
        Turbo::StreamsChannel.stub(:broadcast_action_to, true) do
          GetResponsesCompletionJob.perform_now(conversation: conversation)
        end
      end
    end

    assert_equal 2, calls.size
    assert_equal [ { role: "user", content: "Please help" } ], calls[0][:messages]
    assert_equal "resp_1", calls[1][:kwargs][:previous_response_id]
    assert_equal [ { type: "function_call_output", call_id: "call_1", output: "tool output" } ], calls[1][:kwargs][:input]

    assistant_messages = conversation.reload.messages.role_assistant
    assert_equal 2, assistant_messages.count
    assert assistant_messages.first.tool_calls.present?
    assert_equal "Final assistant reply", assistant_messages.last.content
  end

  test "uses full history for stateless providers between tool turns" do
    conversation = conversations(:teacher_generic_conversation)
    conversation.messages.delete_all
    conversation.messages.create!(role: :user, content: "Please help")

    fake_client = Object.new
    calls = []
    response_index = 0
    responses = [
      {
        "id" => "resp_1",
        "status" => "completed",
        "output" => [
          {
            "type" => "function_call",
            "id" => "fc_1",
            "name" => "list_courses",
            "call_id" => "call_1",
            "arguments" => {}.to_json
          }
        ]
      },
      {
        "id" => "resp_2",
        "status" => "completed",
        "output" => [
          { "type" => "message", "content" => [ { "type" => "output_text", "text" => "Final assistant reply" } ] }
        ]
      }
    ]

    fake_client.define_singleton_method(:stateful_supported?) { false }
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      calls << { messages: messages, kwargs: kwargs }
      response_index += 1
    end
    fake_client.define_singleton_method(:last_response_hash) do
      responses[response_index - 1]
    end
    fake_client.define_singleton_method(:output_text) do |response_hash|
      response_hash["id"] == "resp_2" ? "Final assistant reply" : ""
    end

    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:conversation_flow_tools) { [] }
    fake_adapter.define_singleton_method(:function_calls) do |response_hash|
      Array(response_hash["output"]).select { |item| item["type"] == "function_call" }
    end
    fake_adapter.define_singleton_method(:function_call_outputs) do |_calls|
      [ { id: "fco_1", type: "function_call_output", call_id: "call_1", output: "tool output" } ]
    end
    fake_adapter.define_singleton_method(:function_calls_as_chat_tool_calls) do |calls_for_message|
      calls_for_message.map do |call|
        {
          "type" => "function",
          "id" => call["call_id"],
          "response_item_id" => call["id"],
          "function" => { "name" => call["name"], "arguments" => call["arguments"] }
        }
      end
    end

    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_client }) do
      ResponsesFunctionCallAdapter.stub(:new, ->(**_kwargs) { fake_adapter }) do
        Turbo::StreamsChannel.stub(:broadcast_action_to, true) do
          GetResponsesCompletionJob.perform_now(conversation: conversation)
        end
      end
    end

    assert_equal 2, calls.size
    assert_equal [ { role: "user", content: "Please help" } ], calls[0][:messages]
    assert_equal({ input: nil, previous_response_id: nil }, calls[1][:kwargs])
    assert_nil calls[1][:kwargs][:previous_response_id]
    assert_nil calls[1][:kwargs][:input]

    second_messages = calls[1][:messages]
    assert_equal "user", second_messages[0][:role]
    assert_equal "assistant", second_messages[1][:role]
    assert second_messages[1][:tool_calls].present?
    assert_equal "tool", second_messages[2][:role]
    assert_equal "call_1", second_messages[2][:tool_call_id]
    assert_equal "tool output", second_messages[2][:content]
  end

  test "does not delete latest user message on OpenAiError when a newer tool message exists" do
    conversation = conversations(:teacher_generic_conversation)
    conversation.messages.delete_all
    user_message = conversation.messages.create!(role: :user, content: "Yes")

    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |_messages = nil, **_kwargs|
      conversation.messages.create!(
        role: :tool,
        content: "Tool output after user message",
        tool_call_id: "tool_Show_On_Chalkboard_1"
      )
      raise OpenAiError, "Empty response from LLM."
    end
    fake_client.define_singleton_method(:last_response_hash) { nil }
    fake_client.define_singleton_method(:output_text) { |_response_hash| "" }

    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:conversation_flow_tools) { [] }
    fake_adapter.define_singleton_method(:function_calls) { |_response_hash| [] }
    fake_adapter.define_singleton_method(:function_call_outputs) { |_calls| [] }
    fake_adapter.define_singleton_method(:function_calls_as_chat_tool_calls) { |_calls| [] }

    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_client }) do
      ResponsesFunctionCallAdapter.stub(:new, ->(**_kwargs) { fake_adapter }) do
        Turbo::StreamsChannel.stub(:broadcast_update_to, true) do
          Turbo::StreamsChannel.stub(:broadcast_remove_to, true) do
            assert_raises(OpenAiError) do
              GetResponsesCompletionJob.perform_now(conversation: conversation)
            end
          end
        end
      end
    end

    assert Message.exists?(id: user_message.id), "User message should not be deleted when a newer tool message exists"
  end

  test "blank assistant turn removes placeholder and shows warning" do
    conversation = conversations(:teacher_generic_conversation)
    conversation.messages.delete_all
    conversation.messages.create!(role: :user, content: "Hello")

    fake_client = Object.new
    fake_client.define_singleton_method(:complete) { |_messages = nil, **_kwargs| nil }
    fake_client.define_singleton_method(:last_response_hash) do
      {
        "id" => "resp_empty",
        "status" => "completed",
        "output" => []
      }
    end
    fake_client.define_singleton_method(:output_text) { |_response_hash| "" }

    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:conversation_flow_tools) { [] }
    fake_adapter.define_singleton_method(:function_calls) { |_response_hash| [] }
    fake_adapter.define_singleton_method(:function_call_outputs) { |_calls| [] }
    fake_adapter.define_singleton_method(:function_calls_as_chat_tool_calls) { |_calls| [] }

    warning_calls = []
    remove_calls = []

    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_client }) do
      ResponsesFunctionCallAdapter.stub(:new, ->(**_kwargs) { fake_adapter }) do
        Turbo::StreamsChannel.stub(:broadcast_update_to, ->(*args, **kwargs) { warning_calls << { args: args, kwargs: kwargs } }) do
          Turbo::StreamsChannel.stub(:broadcast_remove_to, ->(*args, **kwargs) { remove_calls << { args: args, kwargs: kwargs } }) do
            Turbo::StreamsChannel.stub(:broadcast_action_to, true) do
              GetResponsesCompletionJob.perform_now(conversation: conversation)
            end
          end
        end
      end
    end

    assert_equal 0, conversation.reload.messages.role_assistant.count
    assert warning_calls.any? { |call| call.dig(:kwargs, :target) == "flash_bar" }
    assert remove_calls.any? { |call| call.dig(:kwargs, :target) == "new_message" }
  end

  test "blank terminal turn after tool calls shows warning instead of completion event" do
    conversation = conversations(:teacher_generic_conversation)
    conversation.messages.delete_all
    conversation.messages.create!(role: :user, content: "Please help")

    fake_client = Object.new
    calls = []
    response_index = 0
    responses = [
      {
        "id" => "resp_1",
        "status" => "completed",
        "output" => [
          {
            "type" => "function_call",
            "name" => "list_courses",
            "call_id" => "call_1",
            "arguments" => {}.to_json
          }
        ]
      },
      {
        "id" => "resp_2",
        "status" => "completed",
        "output" => []
      }
    ]

    fake_client.define_singleton_method(:complete) do |_messages = nil, **kwargs|
      calls << kwargs
      response_index += 1
    end
    fake_client.define_singleton_method(:last_response_hash) do
      responses[response_index - 1]
    end
    fake_client.define_singleton_method(:output_text) { |_response_hash| "" }

    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:conversation_flow_tools) { [] }
    fake_adapter.define_singleton_method(:function_calls) do |response_hash|
      Array(response_hash["output"]).select { |item| item["type"] == "function_call" }
    end
    fake_adapter.define_singleton_method(:function_call_outputs) do |_calls|
      [ { type: "function_call_output", call_id: "call_1", output: "tool output" } ]
    end
    fake_adapter.define_singleton_method(:function_calls_as_chat_tool_calls) do |calls_for_message|
      calls_for_message.map do |call|
        {
          "type" => "function",
          "id" => call["call_id"],
          "function" => { "name" => call["name"], "arguments" => call["arguments"] }
        }
      end
    end

    warning_calls = []
    remove_calls = []
    dispatch_calls = []

    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_client }) do
      ResponsesFunctionCallAdapter.stub(:new, ->(**_kwargs) { fake_adapter }) do
        Turbo::StreamsChannel.stub(:broadcast_update_to, ->(*args, **kwargs) { warning_calls << { args: args, kwargs: kwargs } }) do
          Turbo::StreamsChannel.stub(:broadcast_remove_to, ->(*args, **kwargs) { remove_calls << { args: args, kwargs: kwargs } }) do
            Turbo::StreamsChannel.stub(:broadcast_action_to, ->(*args, **kwargs) { dispatch_calls << { args: args, kwargs: kwargs } }) do
              GetResponsesCompletionJob.perform_now(conversation: conversation)
            end
          end
        end
      end
    end

    assert_equal 2, calls.size
    assert_equal "resp_1", calls[1][:previous_response_id]
    assert_equal 1, conversation.reload.messages.role_assistant.count
    assert warning_calls.any? { |call| call.dig(:kwargs, :target) == "flash_bar" }
    assert remove_calls.any? { |call| call.dig(:kwargs, :target) == "new_message" }
    assert dispatch_calls.none? { |call| call.dig(:kwargs, :action) == :dispatch_event }
  end
end
