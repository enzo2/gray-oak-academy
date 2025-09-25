class AddResourceIdToApplets < ActiveRecord::Migration[8.0]
  def change
    add_reference :applets, :resource, null: true, foreign_key: true
  end
end
