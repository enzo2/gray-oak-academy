require "test_helper"

class LessonProgressTest < ActiveSupport::TestCase
  test "build_task_system_prompt includes lesson details and weighted approved observations" do
    student = users(:student)
    lesson = lessons(:one)
    lesson_progress = LessonProgress.find_or_create_by!(student: student, lesson: lesson)

    travel_to Time.zone.parse("2026-01-01 12:00:00 UTC") do
      Observation.create!(
        student: student,
        content: "OBS_HIGH_CONFIDENCE",
        status: :approved,
        relevance_weight: 1.0,
        last_validated_at: Time.current
      )
      Observation.create!(
        student: student,
        content: "OBS_MODERATE_CONFIDENCE",
        status: :approved,
        relevance_weight: 0.5,
        last_validated_at: Time.current
      )
      Observation.create!(
        student: student,
        content: "OBS_LOW_CONFIDENCE",
        status: :approved,
        relevance_weight: 0.4,
        created_at: 220.days.ago
      )

      prompt = lesson_progress.build_task_system_prompt
      assert_includes prompt, "Course: #{lesson.course.title}"
      assert_includes prompt, "Lesson Title: #{lesson.title}"
      assert_includes prompt, "Student's name: #{student.name}"
      assert_includes prompt, "Resources marked as available:"
      assert_includes prompt, "[high confidence] OBS_HIGH_CONFIDENCE"
      assert_includes prompt, "[moderate confidence] OBS_MODERATE_CONFIDENCE"
      assert_includes prompt, "[low confidence] OBS_LOW_CONFIDENCE"
    end
  end
end
