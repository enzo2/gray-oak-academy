class CreateMemories < ActiveRecord::Migration[8.0]
  def change
    create_table :memories do |t|
      t.belongs_to :student, foreign_key: { to_table: :users }, null: false
      t.belongs_to :author, foreign_key: { to_table: :users } # can be null if authored by LLM
      t.belongs_to :student_report, foreign_key: true, index: false # in case the memory originates from a report
      t.text :body, null: false
      t.boolean :hidden_from_student, default: false, null: false

      # No need to add index for student as it's already indexed via belongs_to

      t.timestamps
    end

    reversible do |dir|
      # Non-reversible change
      dir.up { add_enum_value :prompt_category, "memories_semantic_merge", after: "delegate_to_frontier_llm", if_not_exists: true }
      dir.down { }
    end
  end
end
