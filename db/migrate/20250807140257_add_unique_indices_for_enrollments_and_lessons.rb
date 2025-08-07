class AddUniqueIndicesForEnrollmentsAndLessons < ActiveRecord::Migration[8.0]
  def change
    # Enforce that duplicate enrollments cannot be created
    add_index :enrollments, [ :student_id, :course_id ], unique: true

    # Enforce that duplicate lesson plans cannot be created
    remove_index :lesson_plans, :lesson_id
    add_index :lesson_plans, :lesson_id, unique: true

    # Enforce that duplicate lesson progresses cannot be created
    add_index :lesson_progresses, [ :student_id, :lesson_id ], unique: true
  end
end
