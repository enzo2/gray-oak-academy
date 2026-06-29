class GenerateLessonPlanPipelineJob < ApplicationJob
  queue_as :agent
  limits_concurrency to: 1, key: ->(lesson_plan_id:, **) { "lesson-plan-pipeline-#{lesson_plan_id}" }, duration: 10.minutes

  def perform(lesson_plan_id:, user_id:, propose_resources: false, steering_guidance: nil, source: "lesson_plan_pipeline")
    current_user = User.find(user_id)
    lesson_plan = LessonPlan.find(lesson_plan_id)
    authorize_teacher_access!(current_user, lesson_plan)
    Rails.logger.info(
      "GenerateLessonPlanPipelineJob start source=#{source} lesson_plan=#{lesson_plan_id} propose_resources=#{propose_resources} steering=#{steering_guidance.present?}"
    )

    # Tracks which phase is running so a failure is described in the right terms:
    # content generation uses the teacher's own model (:personal) while resource
    # proposal is a background agent run (:background_agent).
    phase = :content
    lesson_plan.update!(generation_stage: "generating_content", generation_error: nil)
    broadcast_refresh(current_user)

    GenerateLessonPlanContentJob.perform_now(
      lesson_plan,
      current_user,
      steering_guidance: steering_guidance,
      track_stage: false,
      raise_on_error: true
    )

    if propose_resources
      phase = :resources
      lesson_plan.update!(generation_stage: "proposing_resources", generation_error: nil)
      lesson_plan.update_resource_proposal_progress!(
        message: "Lesson content generated; starting resource proposal...",
        detail: "Handing the completed lesson plan to the background agent."
      )
      broadcast_refresh(current_user)

      ProposeResourcesJob.perform_now(
        lesson_plan_id: lesson_plan.id,
        user_id: current_user.id,
        track_stage: true,
        raise_on_error: true,
        source: source
      )
    else
      lesson_plan.update!(generation_stage: "completed", generation_error: nil)
    end
    broadcast_refresh(current_user)
    Rails.logger.info("GenerateLessonPlanPipelineJob finished source=#{source} lesson_plan=#{lesson_plan_id} stage=#{lesson_plan.reload.generation_stage}")
  rescue ActiveRecord::RecordNotFound
    raise
  rescue StandardError => e
    Rails.logger.error("GenerateLessonPlanPipelineJob failed for lesson_plan #{lesson_plan_id} source=#{source}: #{e.message}")
    error_scope = phase == :resources ? :background_agent : :personal
    lesson_plan&.update(generation_stage: "failed", generation_error: GenerationErrorPresenter.friendly(e, scope: error_scope))
    # A morph refresh does not reliably re-render the inline generation status on
    # the lesson-plan edit page, so the failure would otherwise stay hidden until a
    # manual reload. Replace the controls directly so the "failed" status surfaces live.
    broadcast_failure(current_user, lesson_plan) if current_user.present? && lesson_plan.present?
    raise
  end

  private

  def authorize_teacher_access!(current_user, lesson_plan)
    owner_id = lesson_plan.lesson.course.teacher_id
    return if current_user.role_teacher? && (current_user.role_superuser? || owner_id == current_user.id)

    raise ActiveRecord::RecordNotFound
  end

  def broadcast_refresh(current_user)
    Turbo::StreamsChannel.broadcast_refresh_to("teacher_#{current_user.id}-dashboard")
  end

  # Targeted replacement of the generation controls (rather than a page refresh) so
  # the now-"failed" generation status renders live on the open edit page. Re-rendering
  # the button partials also re-enables the actions for retry. Both controls are
  # refreshed because they share generation_stage: the resource-proposal control must
  # be re-rendered too, or it strands an earlier "Proposing..." status after a failure.
  def broadcast_failure(current_user, lesson_plan)
    channel = "teacher_#{current_user.id}-dashboard"
    lesson = lesson_plan.lesson

    Turbo::StreamsChannel.broadcast_replace_to(
      channel,
      target: "lesson-plan-generation-controls",
      partial: "admin/lesson_plans/generate_lesson_plan_button",
      locals: { lesson: lesson, lesson_plan: lesson_plan, current_user: current_user }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      channel,
      target: "resource-proposal-controls",
      partial: "admin/lesson_plans/propose_resources_button",
      locals: { lesson: lesson, lesson_plan: lesson_plan, current_user: current_user }
    )
  end
end
