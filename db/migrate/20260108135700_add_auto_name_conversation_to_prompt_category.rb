class AddAutoNameConversationToPromptCategory < ActiveRecord::Migration[8.0]
  def up
    add_enum_value :prompt_category, "auto_name_conversation", after: "open_ended_student_chat", if_not_exists: true
  end
end
