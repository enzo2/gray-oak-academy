class LessonProgress < ApplicationRecord
  belongs_to :student, class_name: "User"
  belongs_to :lesson
  has_one :conversation
  # includes JSONB fields for :chat_history and :progress_data
end
