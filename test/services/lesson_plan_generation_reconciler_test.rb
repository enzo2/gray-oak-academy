require "test_helper"

class LessonPlanGenerationReconcilerTest < ActiveSupport::TestCase
  # Stub the Solid Queue lookup so the test does not depend on the queue database,
  # which the single-database test environment does not provision.
  class StubLookup
    def initialize(live:)
      @live = live
    end

    def live_job_for?(_lesson_plan_id)
      @live
    end
  end

  setup do
    @lesson_plan = lesson_plans(:one)
  end

  test "marks a stranded in-progress stage failed when no live job backs it" do
    @lesson_plan.update!(generation_stage: "proposing_resources", generation_error: nil)

    reconciled = LessonPlanGenerationReconciler.reconcile(@lesson_plan, live_job_lookup: StubLookup.new(live: false))

    assert reconciled
    assert_equal "failed", @lesson_plan.reload.generation_stage
    assert_includes @lesson_plan.generation_error, "interrupted"
  end

  test "leaves an in-progress stage untouched when a live job still backs it" do
    @lesson_plan.update!(generation_stage: "generating_content", generation_error: nil)

    reconciled = LessonPlanGenerationReconciler.reconcile(@lesson_plan, live_job_lookup: StubLookup.new(live: true))

    refute reconciled
    assert_equal "generating_content", @lesson_plan.reload.generation_stage
  end

  test "does nothing when the lesson plan is not generating" do
    @lesson_plan.update!(generation_stage: "completed", generation_error: nil)

    reconciled = LessonPlanGenerationReconciler.reconcile(@lesson_plan, live_job_lookup: StubLookup.new(live: false))

    refute reconciled
    assert_equal "completed", @lesson_plan.reload.generation_stage
  end

  test "does nothing for an unpersisted lesson plan" do
    new_plan = LessonPlan.new(generation_stage: "proposing_resources")

    reconciled = LessonPlanGenerationReconciler.reconcile(new_plan, live_job_lookup: StubLookup.new(live: false))

    refute reconciled
  end
end
