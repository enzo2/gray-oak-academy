class RemoveTeacherFromLessonPlans < ActiveRecord::Migration[8.1]
  def change
    remove_reference :lesson_plans, :teacher, foreign_key: { to_table: :users }, null: false
  end
end
