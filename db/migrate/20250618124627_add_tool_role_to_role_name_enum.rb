class AddToolRoleToRoleNameEnum < ActiveRecord::Migration[8.0]
  def up
    add_enum_value :role_name, "tool", after: "assistant"
  end
end
