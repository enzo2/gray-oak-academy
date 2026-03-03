require "test_helper"

module Student
  class LessonsControllerTest < ActionDispatch::IntegrationTest
    test "show creates lesson_progress and conversation for accessible lesson" do
      student = users(:student)
      sign_in(student)

      lesson = Lesson.create!(
        course: courses(:one),
        title: "Lesson 1.5",
        approx_duration_min: 30,
        goals: "Practice intermediate addition and subtraction"
      )
      lesson.insert_at(1)
      LessonPlan.create!(
        lesson: lesson,
        content: [ { "Warmup" => "Practice intermediate arithmetic." } ],
        status: "published",
        chalkboard_enabled: true,
        audio: "enabled"
      )

      LessonProgress.where(student: student, lesson: lesson).delete_all

      get student_lesson_path(lesson)
      assert_response :success

      lesson_progress = LessonProgress.find_by(student: student, lesson: lesson)
      assert lesson_progress.present?
      assert lesson_progress.conversation.present?
    end

    test "show redirects with alert when lesson plan is missing" do
      student = users(:student)
      sign_in(student)

      lesson_without_plan = Lesson.create!(
        course: courses(:one),
        title: "Lesson Without Plan",
        approx_duration_min: 25,
        goals: "Understand foundational practice"
      )
      lesson_without_plan.insert_at(1)

      assert_no_difference("LessonProgress.count") do
        get student_lesson_path(lesson_without_plan)
      end

      assert_redirected_to student_root_path
      assert_equal "Lesson plan is not available yet.", flash[:alert]
    end

    test "show renders chalkboard tabs and applet controls for lesson resources" do
      student = users(:student)
      teacher = users(:admin)
      lesson = lessons(:one)
      lesson.lesson_plan.update!(
        status: "published",
        content: [ { "Activity" => "Work through unit conversion examples." } ]
      )

      resource = Resource.create!(
        teacher: teacher,
        category: "Applet",
        description: "Unit converter for metric and imperial values",
        approved: true
      )
      applet = Applet.create!(
        user: teacher,
        resource: resource,
        title: "Unit Converter",
        code: "console.log('unit converter');"
      )
      lesson.lesson_plan.resources << resource unless lesson.lesson_plan.resources.exists?(id: resource.id)

      sign_in(student)
      get student_lesson_path(lesson)

      assert_response :success
      assert_includes response.body, "Applets"
      assert_includes response.body, "Whiteboard"
      assert_includes response.body, "chalkboard-share-applet"
      assert_includes response.body, "Unit Converter"
      assert_includes response.body, run_applet_path(applet)
    end
  end
end
