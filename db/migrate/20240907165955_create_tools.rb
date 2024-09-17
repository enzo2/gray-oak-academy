class CreateTools < ActiveRecord::Migration[7.2]
  def change
    create_table :tools do |t|
      t.string :name
      t.text :description
      t.jsonb :specifications
      t.references :teacher, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
