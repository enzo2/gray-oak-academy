# Reconciles a lesson plan's generation_stage against Solid Queue's authoritative
# job state.
#
# When a generation worker is killed (dev server quit, OOM, deploy), Solid Queue
# reaps the in-flight job into a failed execution WITHOUT running the job's Ruby
# `rescue`, so generation_stage is left stranded at an in-progress value
# ("generating_content" / "proposing_resources"). The lesson-plan controls derive
# their spinner/disabled state from that stage, so they spin forever.
#
# Calling reconcile when the edit page loads flips a stranded stage to "failed" once
# no live job still backs it, which re-enables the controls for a retry. Partial work
# (resources linked during tool turns) is preserved.
class LessonPlanGenerationReconciler
  INTERRUPTED_MESSAGE =
    "The previous generation was interrupted before it could finish (the background worker stopped). " \
    "Any resources already linked were kept — you can run it again."

  def self.reconcile(lesson_plan, live_job_lookup: SolidQueueGenerationJobLookup)
    new(lesson_plan, live_job_lookup: live_job_lookup).reconcile
  end

  def initialize(lesson_plan, live_job_lookup: SolidQueueGenerationJobLookup)
    @lesson_plan = lesson_plan
    @live_job_lookup = live_job_lookup
  end

  # Returns true when a stranded stage was reconciled to "failed", false otherwise.
  def reconcile
    return false unless @lesson_plan.persisted?
    return false unless @lesson_plan.generation_in_progress?
    return false if @live_job_lookup.live_job_for?(@lesson_plan.id)

    # Non-bang update: reconciliation runs on a GET (the edit page), so an unrelated
    # validation failure must not turn a stuck spinner into a 500. If it can't flip
    # the stage, leave it as-is and log — no worse than before reconciling.
    unless @lesson_plan.update(generation_stage: "failed", generation_error: INTERRUPTED_MESSAGE)
      Rails.logger.warn(
        "LessonPlanGenerationReconciler could not flip lesson_plan=#{@lesson_plan.id}: " \
        "#{@lesson_plan.errors.full_messages.join(', ')}"
      )
      return false
    end

    Rails.logger.info(
      "LessonPlanGenerationReconciler marked lesson_plan=#{@lesson_plan.id} failed: no live generation job found"
    )
    true
  end
end
