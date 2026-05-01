require "test_helper"

module Admin
  class LessonsControllerTest < ActionDispatch::IntegrationTest
    test "lesson manager routes do not expose quick lessons by direct url" do
      teacher = users(:admin)
      sign_in(teacher)
      quick_lesson = Course.create!(
        teacher: teacher,
        kind: "quick_lesson",
        title: "Quick Fractions",
        summary: "A quick one-off lesson about common denominators.",
        grade_level: "5"
      )

      get admin_course_lessons_path(quick_lesson)

      assert_response :not_found
    end
  end
end
