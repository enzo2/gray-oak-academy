class LessonPlanAsyncGenerationService
  COOLDOWN_SECONDS = 30

  def initialize(lesson_plan:, current_user:, source:)
    @lesson_plan = lesson_plan
    @current_user = current_user
    @source = source.to_s.presence || "unknown"
  end

  def enqueue_generate_content(propose_resources: false)
    run_with_lock do
      return failure("Generation is already in progress for this lesson plan.") if @lesson_plan.generation_in_progress?
      return failure(cooldown_message) if cooldown_active?

      if propose_resources && !resource_proposal_enabled?
        return failure("Configure OpenAI Agent Runs and Exa API before proposing resources.")
      end

      @lesson_plan.update!(generation_stage: "generating_content", generation_error: nil)
      GenerateLessonPlanPipelineJob.perform_later(
        lesson_plan_id: @lesson_plan.id,
        user_id: @current_user.id,
        propose_resources: propose_resources,
        source: @source
      )
      mark_cooldown!

      success(
        stage: "generating_content",
        message: propose_resources ? "Queued lesson plan generation and resource proposal." : "Queued lesson plan generation."
      )
    end
  end

  def enqueue_propose_resources
    run_with_lock do
      return failure("Configure OpenAI Agent Runs and Exa API before proposing resources.") unless resource_proposal_enabled?
      return failure("Generation is already in progress for this lesson plan.") if @lesson_plan.generation_in_progress?
      return failure(cooldown_message) if cooldown_active?
      return failure("Generate the lesson plan once before proposing resources.") unless @lesson_plan.initial_generation_completed?

      @lesson_plan.update!(generation_stage: "proposing_resources", generation_error: nil)
      ProposeResourcesJob.perform_later(@lesson_plan, @current_user, source: @source)
      mark_cooldown!

      success(stage: "proposing_resources", message: "Queued resource proposal.")
    end
  end

  private

  def run_with_lock(&block)
    # Ensure stage checks and enqueue decisions are atomic for a lesson plan.
    @lesson_plan.with_lock do
      @lesson_plan.reload
      block.call
    end
  end

  def resource_proposal_enabled?
    AppSetting.openai_agent_enabled? && AppSetting.exa_enabled?
  end

  def cooldown_active?
    queued_at = Rails.cache.read(cooldown_cache_key)
    return false if queued_at.blank?

    # Keep cooldown wall-clock based so duplicate clicks/tool calls are rejected
    # even if generation_stage has already moved out of in-progress.
    elapsed = Time.current.to_i - queued_at.to_i
    remaining = COOLDOWN_SECONDS - elapsed
    return false if remaining <= 0

    @cooldown_remaining = remaining
    true
  end

  def mark_cooldown!
    Rails.cache.write(cooldown_cache_key, Time.current.to_i, expires_in: COOLDOWN_SECONDS.seconds)
  end

  def cooldown_cache_key
    "lesson_plan_async_generation:#{@lesson_plan.id}:cooldown"
  end

  def cooldown_message
    "A generation request was just queued. Please wait #{@cooldown_remaining || COOLDOWN_SECONDS} seconds before retrying."
  end

  def success(stage:, message:)
    { ok: true, stage: stage, message: message }
  end

  def failure(message)
    { ok: false, stage: @lesson_plan.generation_stage, message: message }
  end
end
