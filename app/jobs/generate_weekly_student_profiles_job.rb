class GenerateWeeklyStudentProfilesJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = 1.week.ago

    active_student_ids = StudentReport.lesson_reports
      .status_completed
      .where("student_reports.created_at >= ?", cutoff)
      .distinct
      .pluck(:student_id)

    active_students = User.role_student
      .where(id: active_student_ids)
      .where.not(teacher_id: nil)

    now = Time.current
    window_start = now.change(min: 0, sec: 0)
    window_end = window_start + 1.hour
    earliest_time = [ now, window_start ].max

    active_students.find_each do |student|
      run_at = random_time_between(earliest_time, window_end)
      if run_at
        GenerateStudentProfileJob.set(wait_until: run_at).perform_later(student)
      else
        GenerateStudentProfileJob.perform_later(student)
      end
    end
  end

  private

  def random_time_between(start_time, end_time)
    return nil if start_time >= end_time
    Time.zone.at(rand(start_time.to_f...end_time.to_f))
  end
end
