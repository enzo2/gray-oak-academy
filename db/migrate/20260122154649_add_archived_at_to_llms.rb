class AddArchivedAtToLlms < ActiveRecord::Migration[8.0]
  def change
    add_column :llms, :archived_at, :datetime
    add_index :llms, :archived_at
  end
end
