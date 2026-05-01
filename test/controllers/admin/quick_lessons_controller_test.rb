require "test_helper"

module Admin
  class QuickLessonsControllerTest < ActionDispatch::IntegrationTest
    test "index lists teacher quick lessons but not full courses" do
      teacher = users(:admin)
      sign_in(teacher)
      quick_lesson = teacher.taught_courses.create!(
        kind: "quick_lesson",
        title: "Quick Fractions",
        summary: "A quick one-off lesson about common denominators.",
        grade_level: "5"
      )
      quick_lesson.lessons.create!(
        title: "Quick Fractions",
        goals: "Understand common denominators using shared units.",
        approx_duration_min: 20
      )

      get admin_quick_lessons_path

      assert_response :success
      assert_includes response.body, "Quick Fractions"
      assert_not_includes response.body, courses(:one).title
    end

    test "index shows archived quick lessons compactly with delete action" do
      teacher = users(:admin)
      sign_in(teacher)
      quick_lesson = teacher.taught_courses.create!(
        kind: "quick_lesson",
        status: "archived",
        title: "Archived Fractions",
        summary: "A hidden summary that should not be shown on archived rows.",
        grade_level: "5"
      )
      quick_lesson.lessons.create!(
        title: "Archived Fractions",
        goals: "Hidden goals that should not be shown on archived rows.",
        approx_duration_min: 20
      )
      quick_lesson.enrollments.create!(student: users(:student))

      get admin_quick_lessons_path

      assert_response :success
      assert_includes response.body, "Archived Quick Lessons"
      assert_includes response.body, "Archived Fractions"
      assert_includes response.body, "Delete"
      assert_not_includes response.body, "A hidden summary that should not be shown on archived rows."
      assert_not_includes response.body, "Hidden goals that should not be shown on archived rows."
    end

    test "new renders manual quick lesson form" do
      sign_in(users(:admin))

      get new_admin_quick_lesson_path

      assert_response :success
      assert_includes response.body, "New Quick Lesson"
      assert_includes response.body, "Create and Review Plan"
      assert_includes response.body, users(:student).name
    end

    test "create builds quick lesson course and assigns selected students" do
      teacher = users(:admin)
      sign_in(teacher)

      assert_difference -> { Course.quick_lessons.count }, 1 do
        assert_difference -> { Lesson.count }, 1 do
          assert_difference -> { Enrollment.count }, 1 do
            post admin_quick_lessons_path, params: {
              quick_lesson: {
                title: "Quick Fractions",
                grade_level: "5",
                goals: "Understand common denominators using shared units.",
                approx_duration_min: 20,
                student_ids: [ users(:student).id ]
              }
            }
          end
        end
      end

      quick_lesson = teacher.taught_courses.quick_lessons.order(:created_at).last
      lesson = quick_lesson.lessons.first
      assert_redirected_to edit_admin_course_lesson_lesson_plan_path(quick_lesson, lesson)
      assert_equal "Quick Fractions", lesson.title
      assert_equal "Understand common denominators using shared units.", quick_lesson.summary
      assert_includes quick_lesson.students, users(:student)
    end

    test "create rejects invalid manual quick lesson" do
      sign_in(users(:admin))

      assert_no_difference -> { Course.quick_lessons.count } do
        post admin_quick_lessons_path, params: {
          quick_lesson: {
            title: "Q",
            grade_level: "5",
            goals: "Too short",
            approx_duration_min: 20
          }
        }
      end

      assert_response :unprocessable_content
      assert_includes response.body, "prevented this quick lesson from being saved"
    end

    test "destroy removes archived quick lesson assignments before deleting" do
      teacher = users(:admin)
      sign_in(teacher)
      quick_lesson = teacher.taught_courses.create!(
        kind: "quick_lesson",
        status: "archived",
        title: "Archived Fractions",
        summary: "A quick one-off lesson about common denominators.",
        grade_level: "5"
      )
      quick_lesson.lessons.create!(
        title: "Archived Fractions",
        goals: "Understand common denominators using shared units.",
        approx_duration_min: 20
      )
      quick_lesson.enrollments.create!(student: users(:student))

      assert_difference -> { Course.quick_lessons.count }, -1 do
        assert_difference -> { Enrollment.count }, -1 do
          delete admin_quick_lesson_path(quick_lesson)
        end
      end

      assert_redirected_to admin_quick_lessons_path
    end
  end
end
