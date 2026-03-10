require "test_helper"

module Admin
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "admin dashboard hides empty attention and notifications sections" do
      admin = users(:admin)
      sign_in admin

      payload = {
        today: Date.current,
        pending_observations_total: 0,
        students_with_pending_observations: [],
        awaiting_lesson_enrollments: [],
        unread_notifications_total: 0,
        unread_notifications: [],
        recent_activity_items: [],
        lesson_activity_7d: (Date.current - 6.days..Date.current).map { |date| { date: date, started_count: 0, completed_count: 0 } },
        lesson_activity_max_count: 0
      }

      service_called = false
      Admin::TeacherDashboardDataService.stub :call, lambda { |teacher:, **|
        service_called = true
        assert_equal admin, teacher
        payload
      } do
        get admin_root_path
      end

      assert service_called
      assert_response :success
      assert_select "[data-testid='attention-required']", count: 0
      assert_select "[data-testid='awaiting-lessons']"
      assert_select "[data-testid='unread-notifications']", count: 0
      assert_select "[data-testid='recent-activity']"
      assert_select "[data-testid='lesson-activity-overview']"
    end

    test "admin dashboard shows attention and notifications sections when data exists" do
      admin = users(:admin)
      sign_in admin

      payload = {
        today: Date.current,
        pending_observations_total: 2,
        students_with_pending_observations: [
          { student_id: users(:student).id, student_name: users(:student).name, pending_count: 2, latest_pending_at: 5.minutes.ago }
        ],
        awaiting_lesson_enrollments: [],
        unread_notifications_total: 1,
        unread_notifications: [
          Notification.new(event_type: "conversation.context_warning", params: { "user_name" => "Student", "title" => "A Chat" }, created_at: Time.current)
        ],
        recent_activity_items: [],
        lesson_activity_7d: (Date.current - 6.days..Date.current).map { |date| { date: date, started_count: 0, completed_count: 0 } },
        lesson_activity_max_count: 0
      }

      Admin::TeacherDashboardDataService.stub :call, payload do
        get admin_root_path
      end

      assert_response :success
      assert_select "[data-testid='attention-required']"
      assert_select "[data-testid='unread-notifications']"
    end

    test "student is redirected from admin dashboard" do
      student = users(:student)
      sign_in student

      get admin_root_path

      assert_redirected_to student_root_path
      assert_equal "You must be an admin to access this page.", flash[:alert]
    end

    test "admin dashboard renders distinct lesson activity y-axis labels when max count is one" do
      admin = users(:admin)
      sign_in admin

      payload = {
        today: Date.current,
        pending_observations_total: 0,
        students_with_pending_observations: [],
        awaiting_lesson_enrollments: [],
        unread_notifications_total: 0,
        unread_notifications: [],
        recent_activity_items: [],
        lesson_activity_7d: (Date.current - 6.days..Date.current).map.with_index { |date, index|
          { date: date, started_count: index == 6 ? 1 : 0, completed_count: 0 }
        },
        lesson_activity_max_count: 1
      }

      Admin::TeacherDashboardDataService.stub :call, payload do
        get admin_root_path
      end

      assert_response :success
      assert_select "[data-testid='lesson-activity-y-axis-top']", text: "1"
      assert_select "[data-testid='lesson-activity-y-axis-middle']", text: "0.5"
      assert_select "[data-testid='lesson-activity-y-axis-bottom']", text: "0"
    end
  end
end
