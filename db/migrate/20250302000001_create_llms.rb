class CreateLlms < ActiveRecord::Migration[8.0]
  def change
    create_table :llms do |t|
      t.string :model, null: false
      t.string :model_provider
      t.string :api_provider, null: false
      t.index [ :model, :api_provider ], unique: true
      t.integer :context_length
      t.boolean :supports_tool_use
      t.boolean :supports_structured_outputs
      t.boolean :supports_image_input
      t.boolean :supports_image_output
      t.boolean :supports_audio_input
      t.boolean :supports_audio_output
      t.boolean :supports_streaming_audio
      t.jsonb :supported_parameters

      t.datetime :metadata_fetched_at
      t.timestamps
    end

    # Add a reference to completions table
    add_reference :completions, :llm, foreign_key: true, null: true

    reversible do |dir|
      dir.up do
        # In case there are completions without an LLM, we should create one for them
        Completion.find_each(&:validate!)
      end
      dir.down do
        # nothing needed
      end
    end

    # Make the reference required
    change_column_null :completions, :llm_id, false
  end
end
