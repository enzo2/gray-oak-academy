class StudentReport < ApplicationRecord
  # Report may be stored as report (string) or progress_data (JSONB)

  belongs_to :reportable, polymorphic: true # allows any model to have a StudentReport through reportable
  belongs_to :student, class_name: "User", inverse_of: :student_reports, optional: false
  belongs_to :teacher, class_name: "User", inverse_of: :authored_reports, optional: false

  enum :author_type, { ai_generated: "ai_generated", teacher_written: "teacher_written" }, prefix: true
  enum :status, { in_progress: "in_progress", completed: "completed" }, prefix: true
end
