require "test_helper"

class GetLlmCompletionJobStreamingTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  def setup
    ActiveJob::Base.queue_adapter = :test
    @conversation = conversations(:student_generic_conversation)
    @user = @conversation.user
  end

  test "streams assistant content and enqueues TranscribeAudioJob for user audios" do
    # Create a user message that has an attached audio file
    user_msg = @conversation.messages.create!(role: :user, content: "")
    audio = user_msg.audios.create!(content_type: "audio/webm")
    audio.file.attach(io: File.open(Rails.root.join("test/fixtures/files/sample.webm")), filename: "sample.webm", content_type: "audio/webm")

    # Stub OpenaiApiService to return either a streaming or non-streaming fake depending on the call
    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      if handler
        # Streaming fake that calls the provided handler with chunks
        Object.new.tap do |o|
          o.define_singleton_method(:complete) do |*_args|
            handler.call({ "delta" => { "content" => "Hello" } })
            handler.call({ "delta" => { "content" => " world" } })
            handler.call({ "finish_reason" => "stop" })
            handler.call({ "usage" => { "prompt_tokens" => 1, "completion_tokens" => 2, "total_tokens" => 3 } })
            ""
          end
        end
      else
        # Non-streaming fake: return a deterministic transcription for LLM-based STT
        Object.new.tap do |o|
          o.define_singleton_method(:complete) do |*_args|
            "Transcribed fallback text"
          end
        end
      end
    }) do
      # Run the completion job synchronously and process any downstream jobs.
      perform_enqueued_jobs do
        GetLlmCompletionJob.perform_now(conversation: @conversation)
      end
    end

    # The transcription job should have run and removed the audio attachment.
    assert_nil Audio.find_by(id: audio.id), "Audio should have been processed and destroyed"

    # Verify an assistant message was created with the concatenated streamed content
    assistant_msg = @conversation.reload.messages.role_assistant.last
    assert_not_nil assistant_msg, "Assistant message should have been created"
    assert_equal "Hello world", assistant_msg.content
  end

  test "preserves thought_signature on streamed tool calls" do
    @conversation.messages.create!(role: :user, content: "Do the thing")

    captured_tool_calls = nil
    fake_tool_handler = Object.new.tap do |o|
      o.define_singleton_method(:execute_tool_calls) do |tool_calls|
        captured_tool_calls = tool_calls
      end
    end

    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |*_args|
          handler.call({
            "delta" => {
              "tool_calls" => [
                {
                  "index" => 0,
                  "id" => "call_123",
                  "type" => "function",
                  "thought_signature" => "sig_abc",
                  "function" => { "name" => "Complete_Lesson", "arguments" => "{\"x\":" }
                }
              ]
            }
          })
          handler.call({
            "delta" => {
              "tool_calls" => [
                {
                  "index" => 0,
                  "function" => { "arguments" => "1}" }
                }
              ]
            }
          })
          handler.call({ "finish_reason" => "tool_calls" })
          handler.call({ "usage" => { "prompt_tokens" => 1, "completion_tokens" => 2, "total_tokens" => 3 } })
          ""
        end
      end
    }) do
      ToolHandlerService.stub(:new, ->(**_kwargs) { fake_tool_handler }) do
        GetLlmCompletionJob.perform_now(conversation: @conversation)
      end
    end

    assert_not_nil captured_tool_calls
    assert_equal "sig_abc", captured_tool_calls.first[:thought_signature]

    assistant_msg = @conversation.reload.messages.role_assistant.last
    assert_equal "sig_abc", assistant_msg.tool_calls.first["thought_signature"]
    assert_equal "{\"x\":1}", assistant_msg.tool_calls.first.dig("function", "arguments")
  end

  test "preserves nested Gemini metadata across streamed tool call chunks" do
    @conversation.messages.create!(role: :user, content: "Do the thing")

    captured_tool_calls = nil
    fake_tool_handler = Object.new.tap do |o|
      o.define_singleton_method(:execute_tool_calls) do |tool_calls|
        captured_tool_calls = tool_calls
      end
    end

    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |*_args|
          handler.call({
            "delta" => {
              "tool_calls" => [
                {
                  "index" => 0,
                  "id" => "call_123",
                  "type" => "function",
                  "extra_content" => { "google" => { "thought_signature" => "sig_nested" } },
                  "function" => { "name" => "Complete_Lesson", "arguments" => "{\"x\":" }
                }
              ]
            }
          })
          handler.call({
            "delta" => {
              "tool_calls" => [
                {
                  "index" => 0,
                  "extra_content" => { "google" => { "trace_id" => "trace_1" } },
                  "function" => { "arguments" => "1}" }
                }
              ]
            }
          })
          handler.call({ "finish_reason" => "tool_calls" })
          ""
        end
      end
    }) do
      ToolHandlerService.stub(:new, ->(**_kwargs) { fake_tool_handler }) do
        GetLlmCompletionJob.perform_now(conversation: @conversation)
      end
    end

    assert_not_nil captured_tool_calls
    assert_equal "sig_nested", captured_tool_calls.first.dig(:extra_content, :google, :thought_signature)
    assert_equal "trace_1", captured_tool_calls.first.dig(:extra_content, :google, :trace_id)

    assistant_msg = @conversation.reload.messages.role_assistant.last
    assert_equal "sig_nested", assistant_msg.tool_calls.first.dig("extra_content", "google", "thought_signature")
    assert_equal "trace_1", assistant_msg.tool_calls.first.dig("extra_content", "google", "trace_id")
  end

  test "blank response broadcasts warning, completion event, and no assistant message" do
    @conversation.messages.create!(role: :user, content: "Hello?")
    assistant_count_before = @conversation.messages.role_assistant.count
    warning_message = nil
    dispatch_calls = []

    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |*_args|
          handler.call({ "finish_reason" => "stop" })
          handler.call({ "usage" => { "prompt_tokens" => 1, "completion_tokens" => 0, "total_tokens" => 1 } })
          ""
        end
      end
    }) do
      Turbo::StreamsChannel.stub(:broadcast_update_to, ->(*_args, **kwargs) {
        warning_message = kwargs.dig(:locals, :flash, :warning)
      }) do
        Turbo::StreamsChannel.stub(:broadcast_action_to, ->(*args, **kwargs) { dispatch_calls << { args: args, kwargs: kwargs } }) do
          GetLlmCompletionJob.perform_now(conversation: @conversation)
        end
      end
    end

    assistant_msgs = @conversation.reload.messages.role_assistant
    assert_equal assistant_count_before, assistant_msgs.count
    assert_equal "LLM returned an empty response.", warning_message

    completion_event = dispatch_calls.find do |call|
      payload = call[:kwargs].presence || call[:args].last || {}
      action = payload[:action] || payload["action"]
      attributes = payload[:attributes] || payload["attributes"] || {}
      event_name = attributes["event-name"] || attributes[:"event-name"]

      action.to_s == "dispatch_event" && event_name == "llm-completion-finished"
    end

    assert_not_nil completion_event, "Expected llm-completion-finished dispatch event"
    completion_payload = completion_event[:kwargs].presence || completion_event[:args].last || {}
    payload = JSON.parse(completion_payload[:content].to_s)
    assert_equal @conversation.id, payload["conversation_id"]
    assert_equal false, payload["tool_call_pending"]
    assert_nil payload["message_id"]
  end

  test "blank response does not warn after tool message" do
    @conversation.messages.create!(role: :user, content: "Run tool")
    tool_message = @conversation.messages.create!(role: :tool, content: "Tool executed")
    tool_message.update_columns(created_at: Time.current + 1.second, updated_at: Time.current + 1.second)
    assistant_count_before = @conversation.messages.role_assistant.count
    warning_message = nil

    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |*_args|
          handler.call({ "finish_reason" => "stop" })
          handler.call({ "usage" => { "prompt_tokens" => 1, "completion_tokens" => 0, "total_tokens" => 1 } })
          ""
        end
      end
    }) do
      Turbo::StreamsChannel.stub(:broadcast_update_to, ->(*_args, **kwargs) {
        warning_message = kwargs.dig(:locals, :flash, :warning)
      }) do
        GetLlmCompletionJob.perform_now(conversation: @conversation)
      end
    end

    assistant_msgs = @conversation.reload.messages.role_assistant
    assert_equal assistant_count_before, assistant_msgs.count
    assert_nil warning_message
  end

  test "preserves reasoning_details from thinking models" do
    @conversation.messages.create!(role: :user, content: "Think about this")

    reasoning_data = [
      { "id" => "rd_1", "index" => 0, "format" => "anthropic-claude-v1", "type" => "reasoning.text", "text" => "Let me think..." },
      { "id" => "rd_2", "index" => 1, "format" => "anthropic-claude-v1", "type" => "reasoning.text", "text" => "I conclude..." }
    ]

    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |*_args|
          # Stream reasoning_details with explicit indices for separate blocks
          handler.call({ "delta" => { "reasoning_details" => [ reasoning_data[0] ] } })
          handler.call({ "delta" => { "reasoning_details" => [ reasoning_data[1] ] } })
          # Stream content
          handler.call({ "delta" => { "content" => "Here is my answer." } })
          handler.call({ "finish_reason" => "stop" })
          handler.call({ "usage" => { "prompt_tokens" => 100, "completion_tokens" => 50, "total_tokens" => 150 } })
          ""
        end
      end
    }) do
      GetLlmCompletionJob.perform_now(conversation: @conversation)
    end

    assistant_msg = @conversation.reload.messages.role_assistant.last
    assert_not_nil assistant_msg.reasoning_details, "reasoning_details should be saved"
    assert_equal 2, assistant_msg.reasoning_details.length
    assert_equal "rd_1", assistant_msg.reasoning_details.first["id"]
    assert_equal "Here is my answer.", assistant_msg.content

    # Test serialization excludes reasoning_details when no tool_calls present
    # (reasoning is only needed for tool call continuity)
    serialized = Message.for_completion(messages: [ assistant_msg ])
    assert_nil serialized.first[:reasoning_details], "reasoning_details should NOT be serialized without tool_calls"
  end

  test "includes reasoning_details in serialization only when tool_calls present" do
    @conversation.messages.create!(role: :user, content: "Do the thing")

    reasoning_data = [
      { "id" => "rd_1", "index" => 0, "format" => "anthropic-claude-v1", "type" => "reasoning.text", "text" => "Let me think..." }
    ]

    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |*_args|
          # Stream reasoning_details
          handler.call({ "delta" => { "reasoning_details" => reasoning_data } })
          # Stream tool call
          handler.call({
            "delta" => {
              "tool_calls" => [ {
                "index" => 0,
                "id" => "call_456",
                "type" => "function",
                "function" => { "name" => "Complete_Lesson", "arguments" => "{}" }
              } ]
            }
          })
          handler.call({ "finish_reason" => "tool_calls" })
          handler.call({ "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 } })
          ""
        end
      end
    }) do
      ToolHandlerService.stub(:new, ->(**_kwargs) {
        Object.new.tap { |o| o.define_singleton_method(:execute_tool_calls) { |_| } }
      }) do
        GetLlmCompletionJob.perform_now(conversation: @conversation)
      end
    end

    assistant_msg = @conversation.reload.messages.role_assistant.last
    assert_not_nil assistant_msg.reasoning_details, "reasoning_details should be saved"
    assert_not_nil assistant_msg.tool_calls, "tool_calls should be present"

    # Test serialization INCLUDES reasoning_details when tool_calls present, preserving non-OpenAI IDs
    serialized = Message.for_completion(messages: [ assistant_msg ])
    assert_equal reasoning_data, serialized.first[:reasoning_details], "reasoning_details should be serialized with non-rs_ IDs preserved"
  end

  test "merges reasoning_details chunks by index" do
    @conversation.messages.create!(role: :user, content: "Think about this")

    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |*_args|
          # Simulate fragmented reasoning chunks with same index (like OpenRouter sends them)
          handler.call({ "delta" => { "reasoning_details" => [
            { "id" => "rd_1", "index" => 0, "format" => "openai-responses-v1", "type" => "reasoning.summary", "summary" => "First " }
          ] } })
          handler.call({ "delta" => { "reasoning_details" => [
            { "index" => 0, "summary" => "part. " }
          ] } })
          handler.call({ "delta" => { "reasoning_details" => [
            { "index" => 0, "summary" => "Second part." }
          ] } })
          handler.call({ "delta" => { "content" => "Done." } })
          handler.call({ "finish_reason" => "stop" })
          handler.call({ "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 } })
          ""
        end
      end
    }) do
      GetLlmCompletionJob.perform_now(conversation: @conversation)
    end

    assistant_msg = @conversation.reload.messages.role_assistant.last
    assert_not_nil assistant_msg.reasoning_details
    assert_equal 1, assistant_msg.reasoning_details.length, "Should have 1 merged entry, not 3 separate ones"
    assert_equal "First part. Second part.", assistant_msg.reasoning_details.first["summary"]
    assert_equal "rd_1", assistant_msg.reasoning_details.first["id"]
    assert_equal "openai-responses-v1", assistant_msg.reasoning_details.first["format"]
    assert_equal "reasoning.summary", assistant_msg.reasoning_details.first["type"]
    assert_equal 0, assistant_msg.reasoning_details.first["index"]
  end

  test "does not delete latest user message on OpenAiError when a newer tool message exists" do
    conversation = @conversation
    user_message = conversation.messages.create!(role: :user, content: "Yes")

    OpenaiApiService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |_messages|
          conversation.messages.create!(
            role: :tool,
            content: "Tool output after user message",
            tool_call_id: "tool_Show_On_Chalkboard_1"
          )
          raise OpenAiError, "Empty response from LLM."
        end
      end
    }) do
      Turbo::StreamsChannel.stub(:broadcast_update_to, true) do
        Turbo::StreamsChannel.stub(:broadcast_remove_to, true) do
          assert_raises(OpenAiError) do
            GetLlmCompletionJob.perform_now(conversation: conversation)
          end
        end
      end
    end

    assert Message.exists?(id: user_message.id), "User message should not be deleted when a newer tool message exists"
  end

  test "broadcasts completion event with tool_call_pending flag for tool-call turns" do
    @conversation.messages.create!(role: :user, content: "Run a tool")

    dispatch_calls = []

    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |*_args|
          handler.call({
            "delta" => {
              "tool_calls" => [ {
                "index" => 0,
                "id" => "call_123",
                "type" => "function",
                "function" => { "name" => "Show_On_Chalkboard", "arguments" => "{}" }
              } ]
            }
          })
          handler.call({ "finish_reason" => "tool_calls" })
          ""
        end
      end
    }) do
      ToolHandlerService.stub(:new, ->(**_kwargs) {
        Object.new.tap { |o| o.define_singleton_method(:execute_tool_calls) { |_tool_calls| } }
      }) do
        Turbo::StreamsChannel.stub(:broadcast_action_to, ->(*args, **kwargs) { dispatch_calls << { args: args, kwargs: kwargs } }) do
          GetLlmCompletionJob.perform_now(conversation: @conversation)
        end
      end
    end

    completion_event = dispatch_calls.find do |call|
      payload = call[:kwargs].presence || call[:args].last || {}
      action = payload[:action] || payload["action"]
      attributes = payload[:attributes] || payload["attributes"] || {}
      event_name = attributes["event-name"] || attributes[:"event-name"]

      action.to_s == "dispatch_event" && event_name == "llm-completion-finished"
    end

    assert_not_nil completion_event, "Expected llm-completion-finished dispatch event"

    completion_payload = completion_event[:kwargs].presence || completion_event[:args].last || {}
    payload = JSON.parse(completion_payload[:content].to_s)
    assert_equal @conversation.id, payload["conversation_id"]
    assert_equal true, payload["tool_call_pending"]
    assert payload["message_id"].present?
  end

  test "broadcasts completion error event on OpenAiError" do
    @conversation.messages.create!(role: :user, content: "Hello")
    dispatch_calls = []

    OpenaiApiService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        o.define_singleton_method(:complete) do |_messages|
          raise OpenAiError, "boom"
        end
      end
    }) do
      Turbo::StreamsChannel.stub(:broadcast_update_to, true) do
        Turbo::StreamsChannel.stub(:broadcast_remove_to, true) do
          Turbo::StreamsChannel.stub(:broadcast_action_to, ->(*args, **kwargs) { dispatch_calls << { args: args, kwargs: kwargs } }) do
            assert_raises(OpenAiError) do
              GetLlmCompletionJob.perform_now(conversation: @conversation)
            end
          end
        end
      end
    end

    error_event = dispatch_calls.find do |call|
      payload = call[:kwargs].presence || call[:args].last || {}
      action = payload[:action] || payload["action"]
      attributes = payload[:attributes] || payload["attributes"] || {}
      event_name = attributes["event-name"] || attributes[:"event-name"]

      action.to_s == "dispatch_event" && event_name == "llm-completion-error"
    end

    assert_not_nil error_event, "Expected llm-completion-error dispatch event"
    error_payload = error_event[:kwargs].presence || error_event[:args].last || {}
    payload = JSON.parse(error_payload[:content].to_s)
    assert_equal @conversation.id, payload["conversation_id"]
  end
end
