class CreateResources < ActiveRecord::Migration[7.2]
  def change
    create_table :resources do |t|
      t.string :category
      t.text :description
      t.string :uri

      t.timestamps
    end
  end
end
