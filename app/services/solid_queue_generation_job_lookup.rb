# Authoritative check, against Solid Queue's own tables, for whether a lesson-plan
# generation job is still live (queued, running, scheduled, or concurrency-blocked)
# for a given lesson plan.
#
# A job is considered live when it has not finished and has not been moved to a
# failed execution. A worker that is killed (dev server quit, OOM, deploy) has its
# in-flight job reaped by Solid Queue into a failed execution WITHOUT running the
# job's Ruby `rescue`, so this lets callers tell "still working" apart from
# "abandoned/failed" without resorting to a wall-clock guess.
module SolidQueueGenerationJobLookup
  module_function

  # Only these classes are enqueued for lesson-plan generation; the content job runs
  # inline (perform_now) inside the pipeline, so it never has its own Solid Queue row.
  GENERATION_JOB_CLASS_NAMES = %w[
    GenerateLessonPlanPipelineJob
    ProposeResourcesJob
  ].freeze

  def live_job_for?(lesson_plan_id)
    SolidQueue::Job
      .where(finished_at: nil, class_name: GENERATION_JOB_CLASS_NAMES)
      .where.missing(:failed_execution)
      .find_each
      .any? { |job| targets_lesson_plan?(job, lesson_plan_id) }
  rescue StandardError => e
    # If Solid Queue can't be reached, stay conservative and assume a job is still
    # live rather than wrongly failing a generation that may actually be running.
    Rails.logger.warn("SolidQueueGenerationJobLookup could not query Solid Queue: #{e.message}")
    true
  end

  def targets_lesson_plan?(job, lesson_plan_id)
    payload = job.arguments
    return false unless payload.is_a?(Hash)

    kwargs = Array(payload["arguments"]).first
    kwargs.is_a?(Hash) && kwargs["lesson_plan_id"].to_i == lesson_plan_id.to_i
  end
end
