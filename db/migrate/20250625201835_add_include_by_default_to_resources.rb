class AddIncludeByDefaultToResources < ActiveRecord::Migration[8.0]
  def change
    add_column :resources, :include_by_default, :boolean
  end
end
