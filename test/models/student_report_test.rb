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
end
