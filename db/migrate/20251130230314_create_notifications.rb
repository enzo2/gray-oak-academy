class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.string :event_type
      t.jsonb :params
      t.datetime :read_at
      t.string :link

      t.timestamps
    end
  end
end
