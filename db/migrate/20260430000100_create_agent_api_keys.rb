class CreateAgentApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_api_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :visible_prefix, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :agent_api_keys, :token_digest, unique: true
    add_index :agent_api_keys, :visible_prefix
    add_index :agent_api_keys, :revoked_at
  end
end
