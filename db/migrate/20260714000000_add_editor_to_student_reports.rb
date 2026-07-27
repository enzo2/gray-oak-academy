class AddEditorToStudentReports < ActiveRecord::Migration[8.2]
  def change
    add_reference :student_reports, :edited_by,
                  foreign_key: { to_table: :users, on_delete: :nullify }
    add_column :student_reports, :edited_at, :datetime
  end
end
