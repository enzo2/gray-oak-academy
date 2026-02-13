class UndoCourseResearchChangesService
  SNAPSHOT_KEYS = %w[
    summary
    outline
    outline_guidance_report_md
    outline_guidance_questions
    outline_guidance_answers
    outline_research
    outline_research_stage
    outline_research_error
    outline_research_run_id
    outline_research_response_id
  ].freeze

  def initialize(course:)
    @course = course
  end

  def capture_prior_state!
    @course.with_lock do
      @course.reload
      return if @course.course_prior_state.present?

      @course.update!(course_prior_state: snapshot_payload)
    end
  end

  def undo!
    @course.with_lock do
      @course.reload
      prior_state = @course.course_prior_state
      return failure("No prior course state is available to undo.") if prior_state.blank?

      attrs = SNAPSHOT_KEYS.index_with { |key| prior_state_value(prior_state, key) }
      attrs["outline_research_stage"] = restore_stage_for_undo(prior_state, attrs)
      attrs["course_prior_state"] = {}
      @course.update!(attrs)
      success("Reverted the latest agent-applied course changes.")
    end
  rescue StandardError => e
    failure("Failed to undo course changes: #{e.message}")
  end

  private

  def snapshot_payload
    SNAPSHOT_KEYS.index_with do |key|
      value = @course.attributes[key]
      value.respond_to?(:deep_dup) ? value.deep_dup : value
    end
  end

  def restore_stage_for_undo(prior_state, attrs)
    stage = prior_state_value(prior_state, "outline_research_stage").to_s
    return stage unless transient_stage?(stage)

    questions = Array(attrs["outline_guidance_questions"])
    anchors = Array(attrs.dig("outline_research", "source_anchors"))
    if questions.any? || anchors.any?
      "awaiting_teacher_input"
    else
      "idle"
    end
  end

  def prior_state_value(prior_state, key)
    prior_state[key] || prior_state[key.to_sym]
  end

  def transient_stage?(stage)
    %w[researching_outline generating_guidance_questions applying_guidance_updates].include?(stage.to_s)
  end

  def success(message)
    { ok: true, message: message }
  end

  def failure(message)
    { ok: false, message: message }
  end
end
