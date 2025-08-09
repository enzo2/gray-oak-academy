class CreateSupportedApis < ActiveRecord::Migration[8.0]
  def change
    create_table :supported_apis do |t|
      t.string :api_base_uri, null: false
      t.text :api_access_token
      t.boolean :enabled, null: false, default: true
      t.text :notes

      t.timestamps
    end

    add_index :supported_apis, :api_base_uri, unique: true
  end
end
