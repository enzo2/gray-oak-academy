class LessonProgress < ApplicationRecord
  belongs_to :student, class_name: "User"
  belongs_to :lesson
  # includes JSONB fields for :chat_history and :progress_data
end
