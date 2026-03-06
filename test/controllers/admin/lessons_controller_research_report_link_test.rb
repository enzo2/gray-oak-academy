require "test_helper"

module Admin
  class LessonsControllerResearchReportLinkTest < ActionDispatch::IntegrationTest
    test "lesson show redirects to lesson plan editor" do
      teacher = users(:admin)
      course = courses(:one)
      lesson = lessons(:one)
      sign_in(teacher)

      get admin_course_lesson_path(course, lesson)

      assert_redirected_to edit_admin_course_lesson_lesson_plan_path(course, lesson)
      assert_equal 303, response.status
    end

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

    test "lessons index shows lesson discussion button when course already has more than five lessons" do
      teacher = users(:admin)
      course = Course.create!(
        teacher: teacher,
        title: "Lesson Review Course",
        summary: "A course created to verify the lessons discussion button threshold.",
        grade_level: "7",
        outline: [ { "Topic 1" => "Details 1" } ]
      )
      sign_in(teacher)

      6.times do |i|
        course.lessons.create!(title: "Extra lesson #{i}", goals: "Sufficient goals text for lesson #{i}.", approx_duration_min: 30)
      end

      get admin_course_lessons_path(course)

      assert_response :success
      assert_includes response.body, "Discuss Lessons with LLM"
      assert_not_includes response.body, ">Generate Lessons<"
    end

    test "lessons index shows generate lessons button when course has five or fewer lessons" do
      teacher = users(:admin)
      course = Course.create!(
        teacher: teacher,
        title: "Lesson Generation Course",
        summary: "A course created to verify the lessons generation button threshold.",
        grade_level: "8",
        outline: [ { "Topic 1" => "Details 1" } ]
      )
      sign_in(teacher)

      course.lessons.create!(title: "Only lesson", goals: "Sufficient lesson goals text.", approx_duration_min: 30)

      get admin_course_lessons_path(course)

      assert_response :success
      assert_includes response.body, "Generate Lessons"
      assert_not_includes response.body, "Discuss Lessons with LLM"
    end

    test "teacher cannot view another teacher lesson" do
      sign_in(users(:admin))

      get admin_course_lesson_path(courses(:two), lessons(:two))

      assert_response :not_found
    end
  end
end
