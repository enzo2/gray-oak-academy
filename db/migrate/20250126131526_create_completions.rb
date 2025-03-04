class CreateCompletions < ActiveRecord::Migration[8.0]
  def change
    create_table :completions do |t|
      t.string :model, index: true # This was added before the Llm model was created. It's automatically transferred over in the model.
      t.string :model_provider, index: true, null: true # See above.
      t.string :api_provider, index: true, null: true # See above.
      t.integer :prompt_tokens, null: true
      t.integer :prompt_audio_tokens, null: true
      t.integer :cached_tokens, null: true
      t.integer :reasoning_tokens, null: true
      t.integer :completion_tokens, null: true
      t.integer :completion_audio_tokens, null: true
      t.integer :total_tokens, null: true
      t.decimal :total_cost, precision: 6, scale: 4, null: true # USD
      t.decimal :cache_discount, precision: 6, scale: 4, null: true # USD
      t.integer :latency, null: true # ms
      t.integer :generation_time, null: true # ms

      t.timestamps
    end
  end
end
