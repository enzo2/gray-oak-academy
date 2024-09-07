class CreateLessons < ActiveRecord::Migration[7.2]
  def change
    create_table :lessons do |t|
      t.string :title
      t.text :goals
      t.integer :approx_duration_min
      t.references :course, null: false, foreign_key: true

      t.timestamps
    end
  end
end
