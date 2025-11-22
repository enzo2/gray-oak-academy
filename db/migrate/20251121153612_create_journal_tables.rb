class CreateJournalTables < ActiveRecord::Migration[8.0]
  def change
    reversible do |dir|
      dir.up { add_enum_value :prompt_category, "generate_observations", if_not_exists: true }
      dir.down { } # No down action possible for add enum
    end

    create_enum :observation_status, [ "pending", "approved", "rejected", "archived" ]

    create_table :observations do |t|
      t.references :student, null: false, foreign_key: { to_table: :users }
      t.references :author, null: true, foreign_key: { to_table: :users }
      t.references :source, polymorphic: true, null: true
      t.enum :status, enum_type: :observation_status, default: "pending", null: false
      t.text :content, null: false
      t.vector :embedding
      t.datetime :last_validated_at
      t.decimal :relevance_weight, default: 1.0, precision: 3, scale: 2

      t.timestamps
    end

    create_table :student_feedbacks do |t|
      t.references :student, null: false, foreign_key: { to_table: :users }
      t.references :lesson_progress, null: true, foreign_key: true
      t.text :content, null: false

      t.timestamps
    end
  end
end
