class CreateResources < ActiveRecord::Migration[7.2]
  def change
    create_table :resources do |t|
      t.string :category
      t.text :description
      t.string :uri
      t.references :teacher, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
