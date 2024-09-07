class CreateTools < ActiveRecord::Migration[7.2]
  def change
    create_table :tools do |t|
      t.string :name
      t.text :description
      t.jsonb :specifications

      t.timestamps
    end
  end
end
