class AddJointNullConstraintMessageContentAndToolCalls < ActiveRecord::Migration[8.0]
  # Content could be null if the message only has tool calls.
  # Add a joint constraint so content OR a tool call is present.
  def up
    change_column_null :messages, :content, true
    add_check_constraint :messages,
      "(content IS NOT NULL) OR (tool_calls IS NOT NULL AND jsonb_array_length(tool_calls) > 0)",
      name: "messages_content_or_tool_calls_present"
  end

  def down
    remove_check_constraint :messages, name: "messages_content_or_tool_calls_present"
    execute "UPDATE messages SET content = '' WHERE content IS NULL"
    change_column_null :messages, :content, false
  end
end
