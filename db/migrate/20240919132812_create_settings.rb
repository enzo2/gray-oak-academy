class CreateSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end
  end
end
