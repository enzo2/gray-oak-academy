require "test_helper"

class Admin::AnalyticsEventsControllerTest < ActionDispatch::IntegrationTest
  def seed_analytics_events(events)
    app = AppSetting.first
    app.update!(log: (app.log || {}).merge("analytics_events" => events))
  end

  test "superuser can view analytics dashboard" do
    superuser = users(:super_user)
    sign_in superuser

    seed_analytics_events(
      [
        {
          "event_type" => "agent_run.failed",
          "category" => "agent_ops",
          "subject" => "Agent Run Failed",
          "message" => "Agent run run_1 failed: boom",
          "link" => "/admin/agent_runs",
          "recipient_ids" => [ superuser.id ],
          "params" => { "run_id" => "run_1" },
          "emitted_at" => Time.current.iso8601
        }
      ]
    )

    get admin_analytics_events_path
    assert_response :success
    assert_includes response.body, "Analytics Events"
    assert_includes response.body, "agent_run.failed"
    assert_includes response.body, "Agent run run_1 failed: boom"
  end

  test "admin is blocked from analytics dashboard" do
    sign_in users(:admin)
    get admin_analytics_events_path

    assert_redirected_to admin_root_path
    assert_equal "You are not authorized to access that.", flash[:alert]
  end

  test "superuser can clear analytics logs" do
    superuser = users(:super_user)
    sign_in superuser
    app = AppSetting.first
    app.update!(log: (app.log || {}).merge("analytics_events" => [ { "event_type" => "agent_run.failed" } ]))

    delete clear_admin_analytics_events_path

    assert_redirected_to admin_analytics_events_path
    assert_equal "Analytics logs cleared.", flash[:notice]
    assert_equal [], Array(app.reload.log["analytics_events"])
  end

  test "admin cannot clear analytics logs" do
    sign_in users(:admin)

    delete clear_admin_analytics_events_path

    assert_redirected_to admin_root_path
    assert_equal "You are not authorized to access that.", flash[:alert]
  end
end
