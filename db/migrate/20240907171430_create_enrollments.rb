class CreateEnrollments < ActiveRecord::Migration[7.2]
  def change
    create_table :enrollments do |t|
      t.references :student, null: false, foreign_key: { to_table: :users }
      t.references :course, null: false, foreign_key: true
      # Should be unique for { :student, :course } - added later.
      t.boolean :completed

      t.timestamps
    end
  end
end
