class StudentReport < ApplicationRecord
  belongs_to :reportable, polymorphic: true
  belongs_to :student, class_name: "User", inverse_of: :student_reports
  belongs_to :teacher, class_name: "User", optional: true, inverse_of: :authored_reports
  belongs_to :lesson, optional: true, inverse_of: :student_reports
  belongs_to :enrollment, optional: true, inverse_of: :student_reports
  belongs_to :course, optional: true, inverse_of: :student_reports

  enum :author_type, { ai_generated: "ai_generated", teacher_written: "teacher_written" }, prefix: true
  enum :status, { in_progress: "in_progress", completed: "completed" }, prefix: true # i.e. lesson, course enrollment
end
