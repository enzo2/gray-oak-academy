class StudentFeedback < ApplicationRecord
  belongs_to :student, class_name: "User"
  belongs_to :lesson_progress, optional: true

  validates :content, presence: true
end
