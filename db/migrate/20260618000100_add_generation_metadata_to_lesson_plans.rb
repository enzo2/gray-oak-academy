class AddGenerationMetadataToLessonPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :lesson_plans, :generation_metadata, :jsonb, default: {}, null: false
  end
end
