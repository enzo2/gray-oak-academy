class AddReasoningDetailsToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :reasoning_details, :jsonb
  end
end
