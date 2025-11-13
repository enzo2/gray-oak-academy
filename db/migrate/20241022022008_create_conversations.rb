class CreateConversations < ActiveRecord::Migration[7.2]
  def change
    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :lesson_progress, null: true, foreign_key: true
      t.string :title, null: false
      t.string :task_system_prompt, null: true # Optional task-specific system prompt for the conversation (should not include the app's base system prompts)

      t.timestamps
    end
  end
end
