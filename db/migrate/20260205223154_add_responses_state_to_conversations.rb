class AddResponsesStateToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :responses_previous_id, :string
    add_column :conversations, :responses_provider, :string
    add_column :conversations, :responses_model, :string
  end
end
