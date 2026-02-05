class AddTagsToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :tags, :string, array: true, default: [], null: false
    add_index :resources, :tags, using: :gin
    add_index :resources, :category
  end
end
