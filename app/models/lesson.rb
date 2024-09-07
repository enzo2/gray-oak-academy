class Lesson < ApplicationRecord
  belongs_to :course
  has_one :teacher, through: :course
  has_one :lesson_plan
  has_many :student_reports, as: :reportable
  has_many :students, through: :course, inverse_of: :lessons
  has_many :lesson_progresses

  def completed_by?(student)
    student_reports.exists?(student: student, status: :completed)
  end
end
