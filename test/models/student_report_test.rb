require "test_helper"

class StudentReportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @enrollment = enrollments(:one)
    @lesson = lessons(:one)
    @student = users(:student)
    @teacher = users(:admin)
    @lesson_progress = lesson_progresses(:one)
  end

  test "trigger_course_report_check does not enqueue job if course incomplete" do
    # Enrollment is incomplete

    assert_no_enqueued_jobs only: GenerateCourseReportJob do
      StudentReport.create!(
        student: @student,
        reportable: @lesson_progress,
        author_type: :ai_generated,
        status: :completed,
        progress_data: {}
      )
    end
  end

  test "trigger_course_report_check enqueues job if course completed" do
    # Mark enrollment as potentially complete (by having completed lessons count = total lessons count)
    # Mocking completed? on enrollment is hard since it queries DB.
    # Instead, let's setup the data so the enrollment IS completed after this report.

    # Fixture enrollment :one has course :one. Course :one has lesson :one.
    # We are creating a report for lesson_progress :one (lesson :one).
    # So after this report, the lesson is completed.
    # If this is the only lesson, the course is completed.
    # However, lesson_progress is linked to lesson :one.
    # Let's ensure course :one only has lesson :one?
    # Fixtures: course :one has lesson :one.
    # Wait, fixtures show lesson :one belongs to course :one.
    # And lesson :audio_lesson belongs to course :one.
    # So total lessons = 2.

    # I'll create a new course with 1 lesson for simplicity.
    course = Course.create!(title: "Short Course", summary: "Summary must be long enough.", grade_level: "1", teacher: @teacher)
    lesson = course.lessons.create!(title: "Only Lesson", goals: "Goal must be long enough too.", approx_duration_min: 10)
    enrollment = Enrollment.create!(student: @student, course: course)
    lp = LessonProgress.create!(student: @student, lesson: lesson)

    assert_enqueued_with(job: GenerateCourseReportJob, args: [ enrollment ]) do
      StudentReport.create!(
        student: @student,
        reportable: lp,
        author_type: :ai_generated,
        status: :completed,
        progress_data: {}
      )
    end
  end

  test "trigger_course_report_check skips quick lessons" do
    course = Course.create!(
      title: "Quick Common Denominators",
      summary: "A quick one-off lesson about common denominators.",
      grade_level: "5",
      teacher: @teacher,
      kind: "quick_lesson"
    )
    lesson = course.lessons.create!(
      title: "Common Denominators",
      goals: "Understand common denominators using shared units.",
      approx_duration_min: 20
    )
    Enrollment.create!(student: @student, course: course)
    lp = LessonProgress.create!(student: @student, lesson: lesson)

    assert_no_enqueued_jobs only: GenerateCourseReportJob do
      StudentReport.create!(
        student: @student,
        reportable: lp,
        author_type: :ai_generated,
        status: :completed,
        progress_data: {}
      )
    end
  end

  test "teacher edits preserve origin and update structured report data" do
    report = student_reports(:LessonReport1)

    assert report.apply_teacher_edits(
      {
        "summary" => "Corrected summary",
        "strengths" => "Explains the method clearly\n\nChecks the answer",
        "areas_for_review" => ""
      },
      editor: @teacher
    )

    report.reload
    assert_equal "Corrected summary", report.progress_data["summary"]
    assert_equal [ "Explains the method clearly", "Checks the answer" ], report.progress_data["strengths"]
    assert_equal [], report.progress_data["areas_for_review"]
    assert_equal [ "Prefers hands-on learning experiences." ], report.progress_data["memories"]
    assert report.author_type_ai_generated?
    assert_equal @teacher, report.edited_by
    assert_not_nil report.edited_at
  end

  test "teacher correction is used immediately in later lesson context" do
    report = StudentReport.create!(
      student: @student,
      teacher: @teacher,
      reportable: @lesson_progress,
      progress_data: { "summary" => "Original summary" },
      author_type: :ai_generated,
      status: :completed
    )

    assert report.apply_teacher_edits({ "summary" => "Corrected continuity summary" }, editor: @teacher)

    assert_includes @enrollment.lesson_history_for_prompt, "Corrected continuity summary"
  end

  test "teacher edit validates unusual structured fields without losing submitted text" do
    report = student_reports(:LessonReport1)
    report.update!(progress_data: report.progress_data.merge("evidence" => { "score" => 3 }))
    original_data = report.progress_data.deep_dup

    refute report.apply_teacher_edits({ "evidence" => "not valid json" }, editor: @teacher)

    assert_includes report.errors[:evidence], "must contain valid JSON"
    assert_equal "not valid json", report.editable_field_value("evidence")
    assert_equal original_data, report.reload.progress_data
    assert_nil report.edited_at
  end

  test "teacher edit preserves unusual JSON values submitted by the full form" do
    report = student_reports(:LessonReport1)
    report.update!(progress_data: report.progress_data.merge(
      "evidence" => [ { "score" => 3, "verified" => false } ],
      "mastered" => false,
      "attempts" => 2
    ))
    fields = report.editable_fields.keys.index_with { |key| report.editable_field_value(key) }
    fields["summary"] = "Corrected summary"

    assert report.apply_teacher_edits(fields, editor: @teacher)

    report.reload
    assert_equal "Corrected summary", report.progress_data["summary"]
    assert_equal [ { "score" => 3, "verified" => false } ], report.progress_data["evidence"]
    assert_equal false, report.progress_data["mastered"]
    assert_equal 2, report.progress_data["attempts"]
  end

  test "student cannot be recorded as a report editor" do
    report = student_reports(:LessonReport1)

    refute report.apply_teacher_edits({ "summary" => "Student edit" }, editor: @student)

    assert_includes report.errors[:edited_by], "must be a teacher"
    assert_equal "Did well", report.reload.progress_data["summary"]
  end
end
