require "test_helper"

class AnalyticsSubscriberTest < ActiveSupport::TestCase
  setup do
    @app_setting = AppSetting.settings
    @app_setting.update!(log: @app_setting.log.merge("analytics_events" => []))
  end

  test "records analytics event for Events::Base payload when superuser exists" do
    superuser = users(:super_user)
    student = users(:student)
    event = Events::UserSignup.new(
      recipient_ids: superuser.id,
      link: "/admin/students",
      new_user_name: student.name,
      new_user_email: student.email,
      new_user_id: student.id
    )

    AnalyticsSubscriber.new.emit(payload: event)

    events = Array(@app_setting.reload.log["analytics_events"])
    assert_equal 1, events.size
    entry = events.first
    assert_equal "user.signup", entry["event_type"]
    assert_equal "important", entry["category"]
    assert_equal "/admin/students", entry["link"]
    assert_equal [ superuser.id ], entry["recipient_ids"]
    assert_equal student.email, entry.dig("params", "new_user_email")
    assert entry["message"].present?
    assert entry["emitted_at"].present?
  end

  test "ignores non-events payloads" do
    AnalyticsSubscriber.new.emit(payload: { bogus: true })
    assert_equal [], Array(@app_setting.reload.log["analytics_events"])
  end

  test "does not record when there are no superusers" do
    User.stub(:role_superuser, User.none) do
      event = Events::UserSignup.new(
        recipient_ids: users(:admin).id,
        link: "/admin/students",
        new_user_name: "Any User",
        new_user_email: "any@example.com",
        new_user_id: 999
      )
      AnalyticsSubscriber.new.emit(payload: event)
    end

    assert_equal [], Array(@app_setting.reload.log["analytics_events"])
  end
end
