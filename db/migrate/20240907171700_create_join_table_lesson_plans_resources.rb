class CreateJoinTableLessonPlansResources < ActiveRecord::Migration[7.2]
  def change
    create_join_table :lesson_plans, :resources# , column_options: { null: true }
  end
end
