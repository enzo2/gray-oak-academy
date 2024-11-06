class ChangeToolsNameAndDescriptionToGenerated < ActiveRecord::Migration[8.0]
  def change
    remove_column :tools, :name, :string
    remove_column :tools, :description, :text

    add_column :tools, :name, :virtual, type: :string, as: "specifications->>'name'", stored: true
    add_column :tools, :description, :virtual, type: :string, as: "specifications->>'description'", stored: true
  end
end
