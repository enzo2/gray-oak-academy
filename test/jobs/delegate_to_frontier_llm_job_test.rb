require "test_helper"

class DelegateToFrontierLlmJobTest < ActiveJob::TestCase
  test "uses OpenAI native web_search when Exa is not configured" do
    teacher = users(:admin)
    app = AppSetting.first
    original_exa_key = ENV["EXA_API_KEY"]
    ENV.delete("EXA_API_KEY")
    app.update!(openai_agent_model: "gpt-5.2", exa_api_key: nil)
    supported_apis(:openai).update!(enabled: true, api_access_token: "sk-test")

    fake_service = Object.new
    calls = {}
    fake_service.define_singleton_method(:complete) do |messages, **kwargs|
      calls[:complete_messages] = messages
      calls[:complete_kwargs] = kwargs
      { "id" => "resp_123", "status" => "queued" }
    end
    fake_service.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      calls[:wait_response_id] = response_id
      calls[:wait_kwargs] = kwargs
      { "id" => response_id, "status" => "completed", "output" => [], "usage" => {} }
    end
    fake_service.define_singleton_method(:output_text) do |_response_hash|
      "Agent result"
    end

    captured_new_kwargs = nil

    begin
      Prompt.stub(:get_prompt, ->(category:, user:) { "#{category}-prompt-for-#{user.id}" }) do
        User.stub(:role_superuser, User.none) do
          OpenaiResponsesService.stub(:new, ->(**kwargs) { captured_new_kwargs = kwargs; fake_service }) do
            result = DelegateToFrontierLlmJob.perform_now(teacher, "Build a course outline", source: "test")
            assert_equal "Agent result", result
          end
        end
      end
    ensure
      ENV["EXA_API_KEY"] = original_exa_key
    end

    assert_equal teacher, captured_new_kwargs[:current_user]
    assert_equal true, captured_new_kwargs[:agent_run]
    assert_nil captured_new_kwargs[:base_uri]
    assert_nil captured_new_kwargs[:access_token]
    assert_nil captured_new_kwargs[:model]
    assert_equal [ { type: "web_search" } ], captured_new_kwargs[:provider_native_tools]
    assert_equal [], captured_new_kwargs[:flow_tools]

    assert_equal [ { role: "user", content: "Build a course outline" } ], calls[:complete_messages]
    assert_equal true, calls.dig(:complete_kwargs, :background)
    assert_equal "delegate_to_frontier_llm", calls.dig(:complete_kwargs, :metadata, :run_type)
    assert_equal teacher.id.to_s, calls.dig(:complete_kwargs, :metadata, :teacher_id)
    assert_equal "test", calls.dig(:complete_kwargs, :metadata, :source)

    assert_equal "resp_123", calls[:wait_response_id]
    assert_equal 900, calls.dig(:wait_kwargs, :timeout_seconds)
  end

  test "uses Exa function tool and continues response loop when Exa is configured" do
    teacher = users(:admin)
    app = AppSetting.first
    app.update!(openai_agent_model: "gpt-5.2", exa_api_key: "exa-key")
    supported_apis(:openai).update!(enabled: true, api_access_token: "sk-test")

    fake_service = Object.new
    calls = { complete: [], wait: [] }
    fake_service.define_singleton_method(:complete) do |messages = nil, **kwargs|
      calls[:complete] << { messages: messages, kwargs: kwargs }
      if calls[:complete].size == 1
        { "id" => "resp_123", "status" => "queued" }
      else
        { "id" => "resp_456", "status" => "queued" }
      end
    end
    fake_service.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      calls[:wait] << { response_id: response_id, kwargs: kwargs }
      if response_id == "resp_123"
        {
          "id" => "resp_123",
          "status" => "completed",
          "output" => [
            {
              "type" => "function_call",
              "name" => "exa_websearch",
              "call_id" => "call_1",
              "arguments" => { query: "refraction simulation applet" }.to_json
            }
          ]
        }
      else
        {
          "id" => "resp_456",
          "status" => "completed",
          "output" => [
            { "type" => "message", "content" => [ { "type" => "output_text", "text" => "Agent result via Exa" } ] }
          ]
        }
      end
    end
    fake_service.define_singleton_method(:output_text) do |_response_hash|
      "Agent result via Exa"
    end

    fake_exa_service = Object.new
    exa_queries = []
    fake_exa_service.define_singleton_method(:search) do |**kwargs|
      exa_queries << kwargs[:query]
      {
        "results" => [
          { "title" => "Refraction demo", "url" => "https://example.com/refraction", "text" => "demo content" }
        ]
      }
    end

    captured_new_kwargs = nil

    Prompt.stub(:get_prompt, ->(category:, user:) { "#{category}-prompt-for-#{user.id}" }) do
      User.stub(:role_superuser, User.none) do
        ExaApiService.stub(:new, ->(**_kwargs) { fake_exa_service }) do
          OpenaiResponsesService.stub(:new, ->(**kwargs) { captured_new_kwargs = kwargs; fake_service }) do
            result = DelegateToFrontierLlmJob.perform_now(teacher, "Build a course outline", source: "test")
            assert_equal "Agent result via Exa", result
          end
        end
      end
    end

    assert_equal [], captured_new_kwargs[:provider_native_tools]
    assert_equal true, captured_new_kwargs[:agent_run]
    assert_nil captured_new_kwargs[:base_uri]
    assert_nil captured_new_kwargs[:access_token]
    assert_nil captured_new_kwargs[:model]
    tool_names = captured_new_kwargs[:flow_tools].map { |tool| tool[:name] }
    assert_includes tool_names, "exa_websearch"
    assert_includes tool_names, "exa_answer"
    assert_equal [ "refraction simulation applet" ], exa_queries

    assert_equal 2, calls[:complete].size
    assert_equal [ { role: "user", content: "Build a course outline" } ], calls[:complete][0][:messages]
    assert_equal true, calls[:complete][0][:kwargs][:background]
    assert_nil calls[:complete][1][:messages]
    assert_equal "resp_123", calls[:complete][1][:kwargs][:previous_response_id]
    assert_equal true, calls[:complete][1][:kwargs][:background]

    tool_outputs = calls[:complete][1][:kwargs][:input]
    assert_equal "function_call_output", tool_outputs[0][:type]
    assert_equal "call_1", tool_outputs[0][:call_id]
    assert_includes tool_outputs[0][:output], "refraction"
  end

  test "handles exa_answer function tool call and continues response loop" do
    teacher = users(:admin)
    app = AppSetting.first
    app.update!(openai_agent_model: "gpt-5.2", exa_api_key: "exa-key")
    supported_apis(:openai).update!(enabled: true, api_access_token: "sk-test")

    fake_service = Object.new
    calls = { complete: [], wait: [] }
    fake_service.define_singleton_method(:complete) do |messages = nil, **kwargs|
      calls[:complete] << { messages: messages, kwargs: kwargs }
      if calls[:complete].size == 1
        { "id" => "resp_123", "status" => "queued" }
      else
        { "id" => "resp_456", "status" => "queued" }
      end
    end
    fake_service.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      calls[:wait] << { response_id: response_id, kwargs: kwargs }
      if response_id == "resp_123"
        {
          "id" => "resp_123",
          "status" => "completed",
          "output" => [
            {
              "type" => "function_call",
              "name" => "exa_answer",
              "call_id" => "call_2",
              "arguments" => { query: "What is refraction?" }.to_json
            }
          ]
        }
      else
        {
          "id" => "resp_456",
          "status" => "completed",
          "output" => [
            { "type" => "message", "content" => [ { "type" => "output_text", "text" => "Agent answer result" } ] }
          ]
        }
      end
    end
    fake_service.define_singleton_method(:output_text) do |_response_hash|
      "Agent answer result"
    end

    fake_exa_service = Object.new
    exa_queries = []
    fake_exa_service.define_singleton_method(:answer) do |**kwargs|
      exa_queries << kwargs[:query]
      {
        "answer" => "Refraction is the bending of light as it changes medium.",
        "citations" => [
          { "title" => "Refraction basics", "url" => "https://example.com/refraction-basics" }
        ]
      }
    end

    Prompt.stub(:get_prompt, ->(category:, user:) { "#{category}-prompt-for-#{user.id}" }) do
      User.stub(:role_superuser, User.none) do
        ExaApiService.stub(:new, ->(**_kwargs) { fake_exa_service }) do
          OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_service }) do
            result = DelegateToFrontierLlmJob.perform_now(teacher, "Build a course outline", source: "test")
            assert_equal "Agent answer result", result
          end
        end
      end
    end

    assert_equal [ "What is refraction?" ], exa_queries
    assert_equal 2, calls[:complete].size

    tool_outputs = calls[:complete][1][:kwargs][:input]
    assert_equal "function_call_output", tool_outputs[0][:type]
    assert_equal "call_2", tool_outputs[0][:call_id]
    assert_includes tool_outputs[0][:output], "Refraction is the bending of light"
    assert_includes tool_outputs[0][:output], "https://example.com/refraction-basics"
  end

  test "falls back to legacy reasoning model path when app agent is not enabled" do
    teacher = users(:admin)
    teacher.setting.update!(llm_api_access_token: "test-user-key", reasoning_model_name: "reasoning-model-x")
    AppSetting.first.update!(openai_agent_model: nil)

    fake_client = Object.new
    captured_new_kwargs = nil
    captured_messages = nil
    fake_client.define_singleton_method(:complete) do |messages|
      captured_messages = messages
      "Legacy result"
    end

    Prompt.stub(:get_prompt, ->(category:, user:) { "#{category}-prompt-for-#{user.id}" }) do
      OpenaiApiService.stub(:new, ->(**kwargs) { captured_new_kwargs = kwargs; fake_client }) do
        result = DelegateToFrontierLlmJob.perform_now(teacher, "Analyze this", source: "test")
        assert_equal "Legacy result", result
      end
    end

    assert_equal teacher, captured_new_kwargs[:current_user]
    assert_equal true, captured_new_kwargs[:reasoning_model]
    assert_includes captured_new_kwargs[:task_system_prompt], "delegate_to_frontier_llm-prompt-for-#{teacher.id}"
    assert_equal [ { role: "user", content: "Analyze this" } ], captured_messages
  end
end
