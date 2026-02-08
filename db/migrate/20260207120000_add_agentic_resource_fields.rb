class AddAgenticResourceFields < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :approved, :boolean
    add_column :resources, :content, :text

    add_column :lesson_plans, :generation_stage, :string, default: "idle", null: false
    add_column :lesson_plans, :generation_error, :text

    add_index :lesson_plans, :generation_stage
    add_index :resources, :approved
  end
end
