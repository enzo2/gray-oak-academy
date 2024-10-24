class CreateMessages < ActiveRecord::Migration[7.2]
  def change
    create_enum :role_name, [ "system", "user", "assistant" ]

    create_table :messages do |t|
      t.references :conversation, foreign_key: true
      t.enum :role, enum_type: :role_name, null: false
      t.string :content, null: false

      t.timestamps
    end
  end
end
