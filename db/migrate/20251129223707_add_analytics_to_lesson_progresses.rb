class AddAnalyticsToLessonProgresses < ActiveRecord::Migration[8.1]
  def change
    add_column :lesson_progresses, :completed_at, :datetime
    add_column :lesson_progresses, :duration, :integer # duration in seconds
  end
end
