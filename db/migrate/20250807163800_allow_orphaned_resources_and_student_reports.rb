class AllowOrphanedResourcesAndStudentReports < ActiveRecord::Migration[8.0]
  def change
    change_column_null :resources, :teacher_id, true
    change_column_null :student_reports, :teacher_id, true
  end
end
