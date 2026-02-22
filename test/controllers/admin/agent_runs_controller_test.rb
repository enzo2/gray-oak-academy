require "test_helper"

class Admin::AgentRunsControllerTest < ActionDispatch::IntegrationTest
  def seed_agent_run_logs(logs)
    AgentRun.delete_all
    logs.each { |attrs| AgentRun.create!(attrs) }
  end

  test "superuser can view agent runs dashboard" do
    superuser = users(:super_user)
    sign_in superuser

    seed_agent_run_logs(
      [
        {
          run_id: "run_1",
          response_id: "resp_1",
          status: "failed",
          submitted_at: Time.current.iso8601,
          finished_at: Time.current.iso8601,
          teacher_name: "Admin User",
          teacher_id: users(:admin).id,
          model: "gpt-5.2",
          source: "tool_call",
          duration_seconds: 1.2,
          assistant_turns: 1,
          tool_turn_count: 0,
          tool_call_count: 0,
          reasoning_item_count: 1,
          task_preview: "Preview text",
          error_message: "Request failed"
        }
      ]
    )

    get admin_agent_runs_path
    assert_response :success
    assert_includes response.body, "Agent Runs"
    assert_includes response.body, "Turns"
    assert_includes response.body, "run_1"
  end

  test "fetches run trace with tool calls and assistant output" do
    superuser = users(:super_user)
    sign_in superuser
    seed_agent_run_logs(
      [
        {
          run_id: "run_1",
          response_id: "resp_1",
          status: "completed",
          submitted_at: Time.current.iso8601,
          teacher_name: "Admin User",
          teacher_id: users(:admin).id,
          model: "gpt-5.2",
          source: "tool_call",
          task_preview: "Preview text",
          tool_calls: [
            {
              response_id: "resp_turn_1",
              call_id: "call_1",
              name: "exa_search",
              arguments_preview: "query=refraction physics",
              argument_fingerprint: "abc123"
            },
            {
              response_id: "resp_turn_1",
              call_id: "call_2",
              name: "exa_search",
              arguments_preview: "query=refraction physics",
              argument_fingerprint: "abc123"
            }
          ]
        }
      ]
    )

    fake_service = Object.new
    calls = []

    fake_service.define_singleton_method(:retrieve_response) do |response_id, **kwargs|
      calls << { response_id: response_id, kwargs: kwargs }
      {
        "id" => response_id,
        "metadata" => {
          "task_full" => "FULL TASK PROMPT FROM METADATA"
        },
        "output" => [
          {
            "type" => "message",
            "content" => [
              { "type" => "output_text", "text" => "Assistant output text." }
            ]
          }
        ]
      }
    end

    captured_new_kwargs = nil
    OpenaiResponsesService.stub(:new, ->(**kwargs) { captured_new_kwargs = kwargs; fake_service }) do
      get admin_agent_runs_path(trace_response_id: "resp_1")
    end

    assert_response :success
    assert_equal true, captured_new_kwargs[:agent_run]
    assert_equal false, captured_new_kwargs[:agent_run_require_stateful]
    assert_equal "gpt-5.2", captured_new_kwargs[:model]
    assert_nil captured_new_kwargs[:base_uri]
    assert_equal [ { response_id: "resp_1", kwargs: {} } ], calls
    assert_includes response.body, "Tool Calls"
    assert_includes response.body, "exa_search"
    assert_includes response.body, "call_1"
    assert_includes response.body, "Assistant output text."
    assert_includes response.body, "Repeated Argument Patterns"
    assert_includes response.body, "Submitted Task Prompt"
    assert_includes response.body, "FULL TASK PROMPT FROM METADATA"
  end

  test "uses run-persisted provider base uri when fetching trace" do
    superuser = users(:super_user)
    sign_in superuser
    seed_agent_run_logs(
      [
        {
          run_id: "run_provider",
          response_id: "resp_provider",
          status: "completed",
          submitted_at: Time.current.iso8601,
          teacher_name: "Admin User",
          teacher_id: users(:admin).id,
          model: "gpt-5.2",
          provider_base_uri: "https://api.x.ai/v1/",
          source: "tool_call"
        }
      ]
    )

    fake_service = Object.new
    fake_service.define_singleton_method(:retrieve_response) do |_response_id, **_kwargs|
      { "id" => "resp_provider", "output" => [] }
    end

    captured_new_kwargs = nil
    OpenaiResponsesService.stub(:new, ->(**kwargs) { captured_new_kwargs = kwargs; fake_service }) do
      get admin_agent_runs_path(trace_response_id: "resp_provider")
    end

    assert_response :success
    assert_equal "https://api.x.ai/v1/", captured_new_kwargs[:base_uri]
    assert_equal true, captured_new_kwargs[:agent_run]
    assert_equal false, captured_new_kwargs[:agent_run_require_stateful]
  end

  test "admin is blocked from agent runs dashboard" do
    sign_in users(:admin)
    get admin_agent_runs_path

    assert_redirected_to admin_root_path
    assert_equal "You are not authorized to access that.", flash[:alert]
  end

  test "superuser can clear agent run logs" do
    superuser = users(:super_user)
    sign_in superuser
    AgentRun.create!(run_id: "run_1")

    delete clear_admin_agent_runs_path

    assert_redirected_to admin_agent_runs_path
    assert_equal "Agent run logs cleared.", flash[:notice]
    assert_equal 0, AgentRun.count
  end

  test "admin cannot clear agent run logs" do
    sign_in users(:admin)

    delete clear_admin_agent_runs_path

    assert_redirected_to admin_root_path
    assert_equal "You are not authorized to access that.", flash[:alert]
  end
end
