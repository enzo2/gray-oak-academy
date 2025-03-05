class Conversation < ApplicationRecord
  has_many :messages, -> { order(created_at: :asc) }, dependent: :destroy
  has_many :completions
  belongs_to :user
  belongs_to :lesson_progress, optional: true

  scope :generic, -> { where(lesson_progress_id: nil) }
  scope :belongs_to_lesson, -> { where.not(lesson_progress_id: nil) }

  # Conversations have a task_system_prompt field which is optional.
  # This should not include the base system prompts, which are combined by Prompt.full_system_prompt.
  # The base prompts and the task prompt are injected together by the API wrapper (eg OpenRouterService) upon the first completion request.
end
