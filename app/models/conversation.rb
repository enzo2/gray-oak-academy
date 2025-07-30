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

  def last_prompt_tokens
    completions.last&.prompt_tokens || 0
  end

  # Returns the Llm model instance that will be used, or if it doesn't exist yet (never used), the most recent one used in this conversation.
  # Always returns a valid LLM, since the Llm can only be created by a successful completion.
  def llm_in_use
    model = user.setting.llm_model_name.presence ? user.setting.llm_model_name : ENV["DEFAULT_MODEL"]
    api = user.setting.llm_api_base_uri.presence ? user.setting.llm_api_base_uri : ENV["OPENAI_API_BASE_URI"]
    llm = Llm.find_by(model: model, api_provider: api)
    llm ? llm : completions.last&.llm
    # May return nil if the set LLM has never been used and the conversation is empty, as Llm is created only after the first completion.
  end

  def audio_input_supported?
    llm_in_use&.supports_audio_input?
  end

  # The teacher sets whether raw audio message input is disabled, enabled, or "only" (audio forced, whether raw or STT).
  # This does not affect transcription, which is always available if the user has configured speech-to-text.
  # In the event the LLM does not support audio input, the audio recorder will fall back to transcription.
  def audio_setting
    if lesson_progress # for lesson conversations
      lesson_progress.lesson_plan.audio # Can be "disabled", "enabled", or "only"
    else # for generic conversations
      audio_input_supported? ? "enabled" : "disabled"
    end
  end

  # Check if the current LLM supports audio input, and the conversation is set to allow it.
  def audio_input_permitted?
    audio_input_supported? && audio_setting != "disabled"
  end

  def stt_available?
    user.setting.speech_configured?
  end

  def tts_available?
    user.setting.speech_configured?
  end

  # Auto-read TTS function enabled by default for "only" audio setting
  def auto_read_default
    audio_setting == "only" && user.setting.speech_configured? ? true : false
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
