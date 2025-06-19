class AddToolCallIdToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :tool_call_id, :string
  end
end
