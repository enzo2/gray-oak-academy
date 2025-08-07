class AddIndexToLessonPlansResources < ActiveRecord::Migration[8.0]
  def change
    add_index :lesson_plans_resources, [ :lesson_plan_id, :resource_id ], unique: true
  end
end
