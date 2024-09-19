class CreateCourses < ActiveRecord::Migration[7.2]
  def change
    create_table :courses do |t|
      t.string :title
      t.text :summary
      t.jsonb :outline, default: [] # Array of hashes [{title:details}, ....]
      t.string :grade_level
      t.references :teacher, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
