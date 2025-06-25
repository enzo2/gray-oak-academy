class AddSuggestedResourcesToLessonPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :lesson_plans, :suggested_resources, :jsonb, default: []
  end
end
