require "test_helper"

class DelegateToFrontierLlmJobTest < ActiveJob::TestCase
  test "uses the standard reasoning-model routing pipeline" do
    teacher = users(:admin)
    teacher.setting.update!(llm_api_access_token: "test-user-key", reasoning_model_name: "reasoning-model-x")
    AppSetting.first.update!(openai_agent_model: "gpt-5.2", exa_api_key: "exa-key")

    fake_client = Object.new
    captured_new_kwargs = nil
    captured_messages = nil
    fake_client.define_singleton_method(:complete) do |messages|
      captured_messages = messages
      "Routed result"
    end

    Prompt.stub(:get_prompt, ->(category:, user:) { "#{category}-prompt-for-#{user.id}" }) do
      LlmServiceRouting.stub(:build_completion_client, ->(**kwargs) { captured_new_kwargs = kwargs; fake_client }) do
        result = DelegateToFrontierLlmJob.perform_now(teacher, "Analyze this", source: "test")
        assert_equal "Routed result", result
      end
    end

    assert_equal teacher, captured_new_kwargs[:current_user]
    assert_equal true, captured_new_kwargs[:reasoning_model]
    assert_equal false, captured_new_kwargs[:store]
    assert_includes captured_new_kwargs[:task_system_prompt], "delegate_to_frontier_llm-prompt-for-#{teacher.id}"
    assert_equal [ { role: "user", content: "Analyze this" } ], captured_messages
  end

  test "falls back to the standard model when reasoning model is not configured" do
    teacher = users(:admin)
    teacher.setting.update!(reasoning_model_name: nil, llm_model_name: ENV.fetch("DEFAULT_MODEL"))

    fake_client = Object.new
    captured_new_kwargs = nil
    captured_messages = nil
    fake_client.define_singleton_method(:complete) do |messages|
      captured_messages = messages
      "Fallback result"
    end

    Prompt.stub(:get_prompt, ->(category:, user:) { "#{category}-prompt-for-#{user.id}" }) do
      LlmServiceRouting.stub(:build_completion_client, ->(**kwargs) { captured_new_kwargs = kwargs; fake_client }) do
        result = DelegateToFrontierLlmJob.perform_now(teacher, "Analyze this")
        assert_equal "Fallback result", result
      end
    end

    assert_equal teacher, captured_new_kwargs[:current_user]
    assert_equal true, captured_new_kwargs[:reasoning_model]
    assert_equal false, captured_new_kwargs[:store]
    assert_includes captured_new_kwargs[:task_system_prompt], "delegate_to_frontier_llm-prompt-for-#{teacher.id}"
    assert_equal [ { role: "user", content: "Analyze this" } ], captured_messages
  end
end
