class Lesson < ApplicationRecord
  belongs_to :course
  has_one :teacher, through: :course
  has_one :lesson_plan, dependent: :destroy
  has_many :student_reports, as: :reportable
  has_many :students, through: :course, inverse_of: :lessons
  has_many :lesson_progresses, dependent: :destroy

  # accepts_nested_attributes_for :lesson_plan

  validates :title, presence: true, length: { minimum: 3, maximum: 100 }
  validates :goals, presence: true, length: { minimum: 10, maximum: 1000 }
  validates :approx_duration_min, presence: true, numericality: { greater_than: 0, only_integer: true }

  def completed_by?(student)
    student_reports.exists?(student: student, status: :completed)
  end
end
