class CreateLessonProgresses < ActiveRecord::Migration[7.2]
  def change
    create_table :lesson_progresses do |t|
      t.references :student, null: false, foreign_key:  { to_table: :users }
      t.references :lesson, null: false, foreign_key: true
      t.jsonb :chat_history
      t.jsonb :progress_data

      t.timestamps
    end
  end
end
