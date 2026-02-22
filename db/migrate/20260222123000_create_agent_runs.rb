class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      t.string :run_id, null: false
      t.string :response_id
      t.string :status
      t.string :teacher_name
      t.bigint :teacher_id
      t.string :model
      t.string :provider_base_uri
      t.string :source
      t.string :task_preview
      t.text :task_prompt
      t.string :metadata_version
      t.string :phase
      t.datetime :submitted_at
      t.datetime :finished_at
      t.decimal :duration_seconds, precision: 10, scale: 1
      t.integer :assistant_turns
      t.integer :tool_call_count
      t.integer :tool_turn_count
      t.integer :reasoning_item_count
      t.integer :output_item_count
      t.jsonb :tool_calls, default: [], null: false
      t.jsonb :events, default: [], null: false
      t.text :error_message

      t.timestamps
    end

    add_index :agent_runs, :run_id, unique: true
    add_index :agent_runs, :response_id
    add_index :agent_runs, :submitted_at

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE app_settings
          SET
            log = log - 'agent_run_logs',
            settings = settings - 'agent_run_logs'
        SQL
      end
    end
  end
end
