class CreateImages < ActiveRecord::Migration[8.0]
  def change
    create_enum :content_type, [ "image/png", "image/jpeg", "image/webp" ]

    create_table :images do |t|
      t.references :message, foreign_key: true
      t.string :uri, null: true
      t.enum :content_type, enum_type: :content_type, null: false
      t.string :description, null: true

      t.timestamps
    end
  end
end
