class LessonProgress < ApplicationRecord
  # includes JSONB fields for :chat_history and :progress_data; should not be needed since chat is in the Conversation and progress is in the StudentReport

  belongs_to :student, class_name: "User"
  belongs_to :lesson
  has_one :teacher, through: :lesson
  has_one :conversation
  has_one :student_report, as: :reportable


  def find_or_create_conversation(user)
    conversation || create_conversation!(user)
  end

  def completed?
    student_report.present? && student_report.status_completed?
  end

  private

  def create_conversation!(user)
    conversation = Conversation.create!(
      user: user,
      lesson_progress: self,
      title: lesson.title,
      # This prompt will contain all the information needed to conduct the lesson and evaluate the student
      task_system_prompt: lesson.build_system_prompt
    )

    Message.create!(
      conversation: conversation,
      role: :assistant,
      content: "Hello. Ready to begin?"
    )

    conversation
  end
end
