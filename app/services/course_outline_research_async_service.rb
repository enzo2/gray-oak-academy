class CourseOutlineResearchAsyncService
  def initialize(course:, current_user:, source:)
    @course = course
    @current_user = current_user
    @source = source.to_s.presence || "unknown"
  end

  def enqueue_start
    run_with_lock do
      return failure("Generate an outline before starting research.") if @course.outline.blank?
      return failure("Outline research is already in progress for this course.") if @course.outline_research_in_progress?
      if @course.outline_research_restart_blocked?
        return failure("Outline research review is currently open. Resume or reset the existing review workflow before starting a new run.")
      end
      return failure("Configure OpenAI Agent Runs and Exa API before starting outline research.") unless research_pipeline_enabled?

      @course.update!(
        outline_research_stage: "researching_outline",
        outline_research_error: nil,
        outline_research: {},
        outline_guidance_report_md: nil,
        outline_guidance_questions: [],
        outline_guidance_answers: {},
        outline_research_run_id: nil,
        outline_research_response_id: nil,
        course_prior_state: {}
      )

      EnrichCourseOutlineJob.perform_later(
        course_id: @course.id,
        user_id: @current_user.id,
        source: @source
      )

      emit_analytics_event(
        Events::CourseOutlineResearchStarted,
        stage: @course.outline_research_stage
      )

      success(stage: "researching_outline", message: "Queued outline research.")
    end
  end

  def enqueue_resume(permission_granted:)
    permission = ActiveModel::Type::Boolean.new.cast(permission_granted)

    run_with_lock do
      return failure("You must explicitly allow the agent to modify this course before resuming.") unless permission
      return failure("Configure OpenAI Agent Runs and Exa API before resuming outline research.") unless research_pipeline_enabled?
      return failure("Outline research is currently in progress.") if @course.outline_research_in_progress?
      return failure("Outline research must be awaiting teacher input or failed after apply before it can resume.") unless @course.outline_research_input_open?
      unless @course.outline_research_resumable_run?
        return failure("This failed run cannot be resumed because no prior response id is available. Start a new outline research run.")
      end
      return failure("All research questions must be answered before resuming.") if @course.unanswered_research_question_ids.any?
      return failure("All source anchors must be approved or rejected before resuming.") if @course.pending_source_anchor_count.positive?

      @course.update!(
        outline_research_stage: "applying_guidance_updates",
        outline_research_error: nil
      )

      ResumeCourseOutlineResearchJob.perform_later(
        course_id: @course.id,
        user_id: @current_user.id,
        permission_granted: permission,
        source: @source
      )

      emit_analytics_event(
        Events::CourseOutlineResearchResumeQueued,
        stage: @course.outline_research_stage,
        run_id: @course.outline_research_run_id.to_s,
        question_count: Array(@course.outline_guidance_questions).size,
        source_anchor_count: Array(@course.outline_research_hash["source_anchors"]).size
      )

      success(stage: "applying_guidance_updates", message: "Queued research-apply run.")
    end
  end

  private

  def run_with_lock(&block)
    @course.with_lock do
      @course.reload
      block.call
    end
  end

  def research_pipeline_enabled?
    AppSetting.openai_agent_enabled? && AppSetting.exa_enabled?
  end

  def success(stage:, message:)
    { ok: true, stage: stage, message: message }
  end

  def failure(message)
    { ok: false, stage: @course.outline_research_stage, message: message }
  end

  def emit_analytics_event(event_class, stage:, run_id: "", question_count: 0, source_anchor_count: 0)
    Rails.event.notify(event_class.new(
      recipient_ids: [],
      link: Rails.application.routes.url_helpers.edit_admin_course_path(@course),
      teacher_name: @current_user.name,
      teacher_id: @current_user.id,
      course_id: @course.id,
      course_title: @course.title.to_s,
      source: @source.to_s,
      stage: stage.to_s,
      run_id: run_id.to_s,
      question_count: question_count.to_i,
      source_anchor_count: source_anchor_count.to_i
    ))
  rescue StandardError => e
    Rails.logger.error("CourseOutlineResearchAsyncService analytics event failed course=#{@course.id}: #{e.message}")
  end
end
