class AddAccessToTools < ActiveRecord::Migration[8.0]
  def change
    # By default, tools will be accessible to students
    add_column :tools, :access, :enum, enum_type: :user_role, default: "student", null: false
  end
end
