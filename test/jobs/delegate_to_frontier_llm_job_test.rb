require "test_helper"

class DelegateToFrontierLlmJobTest < ActiveJob::TestCase
  test "uses OpenAI Responses background path when app agent is enabled" do
    teacher = users(:admin)
    app = AppSetting.first
    app.update!(openai_agent_model: "gpt-5.2")
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

    Prompt.stub(:get_prompt, ->(category:, user:) { "#{category}-prompt-for-#{user.id}" }) do
      User.stub(:role_superuser, User.none) do
        OpenaiResponsesService.stub(:new, ->(**kwargs) { captured_new_kwargs = kwargs; fake_service }) do
          result = DelegateToFrontierLlmJob.perform_now(teacher, "Build a course outline", source: "test")
          assert_equal "Agent result", result
        end
      end
    end

    assert_equal supported_apis(:openai).api_base_uri, captured_new_kwargs[:base_uri]
    assert_equal "gpt-5.2", captured_new_kwargs[:model]
    assert_equal "sk-test", captured_new_kwargs[:access_token]
    assert_equal teacher, captured_new_kwargs[:current_user]
    assert_equal [ { type: "web_search" } ], captured_new_kwargs[:native_tools]

    assert_equal [ { role: "user", content: "Build a course outline" } ], calls[:complete_messages]
    assert_equal true, calls.dig(:complete_kwargs, :background)
    assert_equal "delegate_to_frontier_llm", calls.dig(:complete_kwargs, :metadata, :run_type)
    assert_equal teacher.id.to_s, calls.dig(:complete_kwargs, :metadata, :teacher_id)
    assert_equal "test", calls.dig(:complete_kwargs, :metadata, :source)

    assert_equal "resp_123", calls[:wait_response_id]
    assert_equal 900, calls.dig(:wait_kwargs, :timeout_seconds)
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
