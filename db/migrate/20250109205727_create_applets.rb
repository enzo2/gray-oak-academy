class CreateApplets < ActiveRecord::Migration[8.0]
  def change
    create_table :applets do |t|
      t.string :title
      t.text :code
      t.boolean :archived
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
