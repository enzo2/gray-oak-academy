class CreateAudios < ActiveRecord::Migration[8.0]
  def change
    create_table :audios do |t|
      t.references :message, null: false, foreign_key: true
      t.string :content_type, null: false
      t.string :description

      t.timestamps
    end
  end
end
