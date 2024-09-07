class CreateStudentReports < ActiveRecord::Migration[7.2]
  def change
    create_enum :report_author_type, [ "ai_generated", "teacher_written" ]
    create_enum :student_report_status, [ "in_progress", "completed" ]

    create_table :student_reports do |t|
      t.references :reportable, polymorphic: true, null: false
      t.references :student, null: false, foreign_key: { to_table: :users }
      t.references :teacher, null: false, foreign_key: { to_table: :users }
      t.references :lesson, null: false, foreign_key: true
      t.references :enrollment, null: false, foreign_key: true
      t.references :course, null: false, foreign_key: true
      t.enum :author_type, enum_type: :report_author_type, null: false
      t.enum :status, enum_type: :student_report_status, null: false
      t.jsonb :progress_data
      t.text :report

      t.timestamps
    end
  end
end
