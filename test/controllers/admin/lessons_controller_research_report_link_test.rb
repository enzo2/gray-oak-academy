require "test_helper"

module Admin
  class LessonsControllerResearchReportLinkTest < ActionDispatch::IntegrationTest
    test "lessons index shows guidance report link when report exists" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(outline_guidance_report_md: "## Guidance\nUse stronger chronology.")

      get admin_course_lessons_path(course)

      assert_response :success
      assert_includes response.body, "View Guidance Report"
      assert_includes response.body, outline_research_input_admin_course_path(course, anchor: "guidance-report")
    end

    test "lessons index hides guidance report link when report is missing" do
      teacher = users(:admin)
      course = courses(:one)
      sign_in(teacher)
      course.update!(outline_guidance_report_md: nil)

      get admin_course_lessons_path(course)

      assert_response :success
      assert_not_includes response.body, "View Guidance Report"
    end
  end
end
