class CreateLessonPlans < ActiveRecord::Migration[7.2]
  def change
    create_enum :lesson_plan_status, [ "draft", "published", "archived" ]

    create_table :lesson_plans do |t|
      t.jsonb :content, default: [] # Array of hashes [{title:details}, ....]
      t.enum :status, enum_type: :lesson_plan_status, default: "draft", null: false
      t.references :lesson, null: false, foreign_key: true  # Should be unique - changed later.
      t.references :teacher, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
