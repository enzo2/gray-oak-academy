class AddAppSetting < ActiveRecord::Migration[8.0]
  def change
    # Create a singleton AppSetting table that follows the user Setting pattern:
    # a JSONB `settings` column to hold flexible app-level configuration.
    create_table :app_settings do |t|
      t.jsonb :settings, null: false, default: {}
      t.boolean :singleton, default: true, null: false
      t.timestamps
    end

    add_index :app_settings, :singleton, unique: true
  end
end
