class AllowNullReportableOnStudentReports < ActiveRecord::Migration[8.0]
  def change
    change_column_null :student_reports, :reportable_id, true
    change_column_null :student_reports, :reportable_type, true
  end
end
