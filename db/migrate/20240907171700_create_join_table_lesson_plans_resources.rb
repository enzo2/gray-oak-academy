class CreateJoinTableLessonPlansResources < ActiveRecord::Migration[7.2]
  def change
    create_join_table :lesson_plans, :resources
    # Should have index - added later
  end
end
