class GenerateLessonPlanPipelineJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(lesson_plan_id:, **) { "lesson-plan-pipeline-#{lesson_plan_id}" }, duration: 10.minutes

  def perform(lesson_plan_id:, user_id:, propose_resources: false)
    current_user = User.find(user_id)
    lesson_plan = LessonPlan.find(lesson_plan_id)

    lesson_plan.update!(generation_stage: "generating_content", generation_error: nil)
    broadcast_refresh(current_user)

    GenerateLessonPlanContentJob.perform_now(
      lesson_plan,
      current_user,
      track_stage: false,
      raise_on_error: true
    )

    if propose_resources
      lesson_plan.update!(generation_stage: "proposing_resources", generation_error: nil)
      broadcast_refresh(current_user)

      ProposeResourcesJob.perform_now(
        lesson_plan,
        current_user,
        track_stage: false,
        raise_on_error: true
      )
    end

    lesson_plan.update!(generation_stage: "completed", generation_error: nil)
    broadcast_refresh(current_user)
  rescue StandardError => e
    Rails.logger.error("GenerateLessonPlanPipelineJob failed for lesson_plan #{lesson_plan_id}: #{e.message}")
    lesson_plan&.update(generation_stage: "failed", generation_error: e.message)
    broadcast_refresh(current_user) if current_user.present?
    raise
  end

  private

  def broadcast_refresh(current_user)
    Turbo::StreamsChannel.broadcast_refresh_to("teacher_#{current_user.id}-dashboard")
  end
end
