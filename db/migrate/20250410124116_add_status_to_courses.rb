class AddStatusToCourses < ActiveRecord::Migration[8.0]
  def up
    create_enum :course_status, [ "active", "archived" ]
    change_table :courses do |t|
      t.enum :status, enum_type: :course_status, default: "active", null: false
    end
  end
end
