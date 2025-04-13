class Conversation < ApplicationRecord
  has_many :messages, -> { order(created_at: :asc) }, dependent: :destroy
  has_many :completions
  belongs_to :user
  belongs_to :lesson_progress, optional: true

  scope :generic, -> { where(lesson_progress_id: nil) }
  scope :belongs_to_lesson, -> { where.not(lesson_progress_id: nil) }

  # Conversation stores the thread of messages, along with an optional task_system_prompt in a separate field.
  # The task_system_prompt should include the task at hand, and should not include the base system prompts or generative guidelines, which are added in OpenAiApiService.
  # The base prompts and the task prompt are injected together upon the completion request.

  # Returns the LLM used in the last completion.
  def llm_in_use
    completions.last&.llm
  end

  def last_prompt_tokens
    completions.last&.prompt_tokens || 0
  end

  def audio_setting
    if lesson_progress # for lesson conversations
      lesson_progress.lesson_plan.audio # Can be "disabled", "enabled", or "only"
    else # for generic conversations
      llm_in_use&.supports_audio_input ? "enabled" : "disabled"
    end
  end

  def audio_permitted?
    audio_setting == "enabled" || audio_setting == "only"
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
