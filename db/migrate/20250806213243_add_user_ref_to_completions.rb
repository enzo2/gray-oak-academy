class AddUserRefToCompletions < ActiveRecord::Migration[8.0]
  def up
    add_reference :completions, :user, foreign_key: { on_delete: :nullify }

    # Backfill user_id from conversation
    Completion.includes(:conversation).find_each do |completion|
      if completion.conversation
        completion.update_column(:user_id, completion.conversation.user_id)
      end
    end
  end

  def down
    remove_reference :completions, :user
  end
end
