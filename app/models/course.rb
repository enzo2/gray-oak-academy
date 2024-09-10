class Course < ApplicationRecord
  belongs_to :teacher, class_name: "User", inverse_of: :taught_courses
  has_many :students, through: :enrollments, inverse_of: :courses
  has_many :lessons
  has_many :enrollments
  has_many :student_reports, as: :reportable

  validates :grade_level,
            presence: true,
            format: {
              with: /\A([A-Za-z]|[1-9]\d*)\z/,
              message: "must be a single letter or a positive integer"
            }

  def completed_by?(student)
    enrollment.exists?(student: student, completed: true)
  end
end
