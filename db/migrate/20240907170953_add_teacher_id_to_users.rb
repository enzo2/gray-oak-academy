class AddTeacherIdToUsers < ActiveRecord::Migration[7.2]
  def change
    add_reference :users, :teacher, foreign_key: { to_table: :users }, null: true
  end
end
