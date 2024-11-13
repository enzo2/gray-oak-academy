class RemoveColumnsFromStudentReports < ActiveRecord::Migration[8.0]
  def change
    remove_reference :student_reports, :lesson, foreign_key: true
    remove_reference :student_reports, :enrollment, foreign_key: true
    remove_reference :student_reports, :course, foreign_key: true
  end
end
