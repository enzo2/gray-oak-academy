class LessonProgress < ApplicationRecord
  belongs_to :student, class_name: "User"
  belongs_to :lesson
  field :chat_history, :jsonb
  field :progress_data, :jsonb # Store any type of progress data not reflected in the chat
end
