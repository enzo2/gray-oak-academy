class LessonProgress < ApplicationRecord
  belongs_to :student, class_name: "User"
  belongs_to :lesson
  has_one :conversation
  # includes JSONB fields for :chat_history and :progress_data

  def find_or_create_conversation(user)
    conversation || create_conversation!(user)
  end

  private

  def create_conversation!(user)
    conversation = Conversation.create!(
      user: user,
      lesson_progress: self,
      title: lesson.title,
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
