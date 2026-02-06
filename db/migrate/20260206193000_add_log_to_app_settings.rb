class AddLogToAppSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :app_settings, :log, :jsonb, null: false, default: {}
  end
end
