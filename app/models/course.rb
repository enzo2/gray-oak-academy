class Course < ApplicationRecord
  belongs_to :teacher, class_name: "User", inverse_of: :taught_courses
  has_many :students, through: :enrollments, inverse_of: :courses
  has_many :lessons
  has_many :enrollments
  has_many :student_reports, as: :reportable

  def completed_by?(student)
    enrollment.exists?(student: student, completed: true)
  end
end
