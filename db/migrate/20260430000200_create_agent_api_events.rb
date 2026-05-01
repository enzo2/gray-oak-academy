class CreateAgentApiEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_api_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :agent_api_key, null: false, foreign_key: true
      t.string :request_method, null: false
      t.string :path, null: false
      t.string :command
      t.integer :status
      t.jsonb :record_ids, default: {}, null: false
      t.string :error_code
      t.text :error_message
      t.datetime :requested_at, null: false

      t.timestamps
    end

    add_index :agent_api_events, :command
    add_index :agent_api_events, :requested_at
    add_index :agent_api_events, :status
  end
end
