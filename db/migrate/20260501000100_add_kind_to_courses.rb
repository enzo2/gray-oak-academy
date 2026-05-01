class AddKindToCourses < ActiveRecord::Migration[8.1]
  def up
    create_enum :course_kind, [ "full_course", "quick_lesson" ]
    add_column :courses, :kind, :enum, enum_type: :course_kind, null: false, default: "full_course"
    add_index :courses, :kind
  end

  def down
    remove_index :courses, :kind
    remove_column :courses, :kind
    drop_enum :course_kind
  end
end
