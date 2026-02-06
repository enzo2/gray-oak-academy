require "test_helper"

class GenerateWeeklyStudentProfilesJobTest < ActiveJob::TestCase
  def setup
    @teacher = users(:admin)
    @active_student = users(:student)
    @stale_student = users(:student2)

    @active_student.update!(teacher: @teacher)
    @stale_student.update!(teacher: @teacher)

    @course = Course.create!(
      title: "Weekly Profile Course",
      teacher: @teacher,
      summary: "Testing weekly student profile generation",
      grade_level: "5"
    )
    @lesson = Lesson.create!(
      title: "Weekly Profile Lesson",
      course: @course,
      goals: "Complete the lesson",
      approx_duration_min: 30
    )
  end

  test "enqueues profile generation for students with completed lessons in the past week" do
    create_lesson_report(student: @active_student, created_at: Time.zone.parse("2026-02-01 10:00:00"))
    create_lesson_report(student: @stale_student, created_at: Time.zone.parse("2026-01-20 10:00:00"))

    travel_to(Time.zone.parse("2026-02-02 05:00:00")) do
      assert_enqueued_jobs 1, only: GenerateStudentProfileJob do
        GenerateWeeklyStudentProfilesJob.perform_now
      end
    end

    profile_jobs = enqueued_jobs.select { |job| job[:job] == GenerateStudentProfileJob }
    assert_equal 1, profile_jobs.size

    serialized_gid = profile_jobs.first.dig(:args, 0, "_aj_globalid")
    assert_includes serialized_gid, "/User/#{@active_student.id}"
  end

  test "skips orphaned students even if they completed a recent lesson" do
    @active_student.update_column(:teacher_id, nil)
    create_lesson_report(student: @active_student, created_at: Time.zone.parse("2026-02-01 10:00:00"))

    travel_to(Time.zone.parse("2026-02-02 05:00:00")) do
      assert_no_enqueued_jobs only: GenerateStudentProfileJob do
        GenerateWeeklyStudentProfilesJob.perform_now
      end
    end
  end

  test "randomly schedules profile generation between 5 and 6am when multiple students are active" do
    create_lesson_report(student: @active_student, created_at: Time.zone.parse("2026-02-01 10:00:00"))
    create_lesson_report(student: @stale_student, created_at: Time.zone.parse("2026-01-31 10:00:00"))

    travel_to(Time.zone.parse("2026-02-02 05:00:00")) do
      assert_enqueued_jobs 2, only: GenerateStudentProfileJob do
        GenerateWeeklyStudentProfilesJob.perform_now
      end

      profile_jobs = enqueued_jobs.select { |job| job[:job] == GenerateStudentProfileJob }
      window_start = Time.current
      window_end = window_start + 1.hour

      profile_jobs.each do |job|
        assert_not_nil job[:at], "expected randomized scheduling with wait_until"
        run_at = Time.zone.at(job[:at])
        assert_operator run_at, :>=, window_start
        assert_operator run_at, :<=, window_end
      end
    end
  end

  private

  def create_lesson_report(student:, created_at:)
    Enrollment.find_or_create_by!(course: @course, student: student)
    lesson_progress = LessonProgress.find_or_create_by!(lesson: @lesson, student: student)

    StudentReport.create!(
      student: student,
      teacher: @teacher,
      reportable: lesson_progress,
      progress_data: { "summary" => "Completed" },
      author_type: :ai_generated,
      status: :completed,
      created_at: created_at,
      updated_at: created_at
    )
  end
end
