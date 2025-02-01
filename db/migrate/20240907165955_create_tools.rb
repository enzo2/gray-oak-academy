class CreateTools < ActiveRecord::Migration[7.2]
  def change
    create_table :tools do |t|
      t.string :name # REMOVED - include in specifications
      t.text :description # REMOVED - include in specifications
      t.jsonb :specifications
      t.references :teacher, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
