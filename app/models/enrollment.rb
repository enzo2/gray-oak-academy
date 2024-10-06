class Enrollment < ApplicationRecord
  belongs_to :student, class_name: "User", inverse_of: :enrollments
  belongs_to :course
  has_many :student_reports, as: :reportable

  # Calculates the percentage of lessons completed in the course
  def progress_percentage
    return 0 if total_lessons.zero?
    (completed_lessons.to_f / total_lessons * 100).round
  end

  # Returns the number of lessons completed by the student in the course
  def completed_lessons
    student_reports.where(status: :completed).count
  end

  # Returns the total number of lessons in the course
  def total_lessons
    course.lessons.count
  end

  # Whether course has any published lessons not yet completed by student
  def has_available_lesson?
    course.lessons.published.not_completed_by_student(student).exists?
  end

  def next_available_lesson
    course.lessons.published.not_completed_by_student(student).first
  end
end
