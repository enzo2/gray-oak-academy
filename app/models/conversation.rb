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
  #

  # Returns the LLM used in the last completion.
  def llm_in_use
    completions.last&.llm
  end


  def last_prompt_tokens
    completions.last&.prompt_tokens || 0
  end

  # Returns the percentage of the context limit used by the conversation.
  # Return 0 if no context length is available.
  def context_usage
    context_limit = llm_in_use&.context_length
    Rails.logger.debug "Context limit: #{context_limit}"
    return 0 unless context_limit
    last_prompt_tokens.to_f / context_limit.to_f * 100
  end
end
