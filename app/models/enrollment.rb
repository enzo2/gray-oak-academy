class Enrollment < ApplicationRecord
  belongs_to :student, class_name: "User", inverse_of: :enrollments
  belongs_to :course
  has_many :student_reports, as: :reportable, dependent: :nullify # used for course-end reports

  # Enforce no duplicate enrollments
  validates_uniqueness_of :student_id, scope: :course_id, message: "has already enrolled in this course"

  # Scopes filter completed/in_progress based on the presence of an enrollment report
  scope :completed, -> { joins(:student_reports).where(student_reports: { status: :completed }) }
  scope :in_progress, -> { where.not(
      id: joins(:student_reports).where(student_reports: { status: :completed }).select(:id)
  )}

  # Returns the lessons completed by the student, as determined by having a student report
  # (Would not include any lessons that were completed and then deleted)
  def completed_lessons
    course.lessons
      .joins(:student_reports)
      .where(student_reports: { student_id: student.id, status: :completed })
      .order(position: :asc)
  end

  def incomplete_lessons
    course.lessons.where.not(id: completed_lessons.pluck(:id)).order(position: :asc)
  end

  # Returns the number of lessons completed by the student in the course
  def completed_lessons_count
    completed_lessons.count
  end

  # Returns the total number of lessons in the course
  def total_lessons_count
    course.lessons.count
  end

  # Calculates the percentage of lessons completed in the course
  def progress_percentage
    return 0 if total_lessons_count.zero?
    (completed_lessons_count.to_f / total_lessons_count * 100).round
  end

  # Whether course has any published lessons not yet completed by student
  def has_available_lesson?
    incomplete_lessons.published.exists?
  end

  def next_available_lesson
    incomplete_lessons.published.first
  end

  # Determine if enrollment is completed by checking if all lessons have been completed
  def completed?
    return false unless course.lessons.any?
    completed_lessons_count == total_lessons_count
  end

  # When the course is completed, we need to generate a course-end summary report based on all the lesson reports.
  def course_report_check
    # If the course is completed and there are no student reports, generate a course report
    if completed? && !student_reports.exists?
      Rails.logger.info "Found missing enrollment report. Generating report for enrollment #{id}"
      GenerateCourseReportJob.perform_later(self)
    end
  end

  def lesson_history_for_prompt
    unless completed_lessons.empty?
      completed_lessons.map do |lesson|
        report = lesson.student_reports.where(student: student).first
        report_content = report.progress_data.to_s || "Report not available."
        "Lesson #{lesson.position}: #{lesson.title} | Goals: #{lesson.goals} | Student Report:#{report_content}"
      end.join("\n")
    else
      "No previous lessons completed in this course yet."
    end
  end
end
