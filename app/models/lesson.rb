class Lesson < ApplicationRecord
  belongs_to :course
  acts_as_list scope: :course
  has_one :teacher, through: :course
  has_one :lesson_plan, dependent: :destroy
  has_many :students, through: :course, inverse_of: :lessons
  has_many :lesson_progresses# , dependent: :destroy   #if we delete the course/lessons, keep the LessonProgress with its associated StudentReport
  has_many :student_reports, through: :lesson_progresses# , source: :reportable, source_type: "StudentReport"  #?needed

  validates :title, presence: true, length: { minimum: 3, maximum: 100 }
  validates :goals, presence: true, length: { minimum: 10, maximum: 1000 }
  validates :approx_duration_min, presence: true, numericality: { greater_than: 0, only_integer: true }

  scope :published, -> { joins(:lesson_plan).where(lesson_plans: { status: "published" }) }

  def completed_by?(student)
    # Check if the student has a completed StudentReport associated with this lesson
    lesson_progress = lesson_progresses.find_by(student: student)
    return false if lesson_progress.nil?
    lesson_progress.completed?
  end

  # Filters lessons that have been completed by the given student, having an associated StudentReport
  def self.completed_by_student(student)
    joins(:student_reports).where(student_reports: { student_id: student.id, status: :completed })
  end

  # e.g. next_lesson = course.lessons.published.not_completed_by_student(student).first
  def self.not_completed_by_student(student)
    completed_lessons = completed_by_student(student).pluck(:id)
    where.not(id: completed_lessons)
  end

  def find_or_create_progress(student)
    LessonProgress.find_or_create_by(student: student, lesson: self)
  end
end
