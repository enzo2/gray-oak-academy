class AddSuperuserRoleToUserRoleEnum < ActiveRecord::Migration[8.0]
  def up
    add_enum_value :user_role, "superuser", after: "admin"
  end
end
