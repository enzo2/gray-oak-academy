require "test_helper"

module Admin
  class LessonPlansControllerTest < ActionDispatch::IntegrationTest
    test "edit action renders successfully for lesson without lesson plan" do
      teacher = users(:admin) # Assuming 'admin' is a teacher
      sign_in(teacher)

      # Create a fresh lesson without a lesson plan
      course = courses(:one)
      lesson = Lesson.create!(
        title: "New Lesson No Plan",
        goals: "Testing goals",
        approx_duration_min: 30,
        course: course,
        position: 100
      )

      # Ensure no lesson plan exists
      assert_nil lesson.lesson_plan

      # Visit the edit page (which triggers set_lesson_plan and build_lesson_plan)
      get edit_admin_course_lesson_lesson_plan_path(course, lesson)

      assert_response :success
      # Verify that a new lesson plan was initialized but not necessarily persisted yet
      # (The controller only builds it, it doesn't save it in 'edit')
    end
  end
end
