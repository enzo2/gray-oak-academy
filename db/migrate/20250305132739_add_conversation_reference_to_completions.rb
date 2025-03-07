class AddConversationReferenceToCompletions < ActiveRecord::Migration[8.0]
  def change
    add_reference :completions, :conversation, null: true, foreign_key: { on_delete: :nullify }
  end
end
