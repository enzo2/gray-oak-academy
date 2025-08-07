class MakeConversationForeignKeyColumnsNonNull < ActiveRecord::Migration[8.0]
  def change
    change_column_null :messages, :conversation_id, false
    change_column_null :images, :message_id, false
  end
end
