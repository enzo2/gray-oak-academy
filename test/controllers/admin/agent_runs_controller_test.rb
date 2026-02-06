require "test_helper"

class Admin::AgentRunsControllerTest < ActionDispatch::IntegrationTest
  def seed_agent_run_logs(logs)
    app = AppSetting.first
    app.update!(log: app.log.merge("agent_run_logs" => logs))
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
    assert_includes response.body, "run_1"
  end

  test "fetches reasoning trace from standard response payload only" do
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
          task_preview: "Preview text"
        }
      ]
    )

    fake_service = Object.new
    calls = []

    fake_service.define_singleton_method(:retrieve_response) do |response_id, **kwargs|
      calls << { response_id: response_id, kwargs: kwargs }
      {
        "id" => response_id,
        "output" => [
          {
            "type" => "reasoning",
            "summary" => [ { "text" => "Reasoning summary available." } ]
          }
        ]
      }
    end

    OpenaiResponsesService.stub(:new, ->(**_kwargs) { fake_service }) do
      get admin_agent_runs_path(trace_response_id: "resp_1")
    end

    assert_response :success
    assert_equal [ { response_id: "resp_1", kwargs: {} } ], calls
    assert_includes response.body, "Reasoning summary available."
  end

  test "admin is blocked from agent runs dashboard" do
    sign_in users(:admin)
    get admin_agent_runs_path

    assert_redirected_to admin_root_path
    assert_equal "You are not authorized to access that.", flash[:alert]
  end
end
