class Enrollment < ApplicationRecord
  belongs_to :student, class_name: "User", inverse_of: :enrollments
  belongs_to :course
  has_many :student_reports, as: :reportable
end
