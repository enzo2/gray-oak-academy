require "test_helper"

class SolidQueueGenerationJobLookupTest < ActiveSupport::TestCase
  class FakeJob
    attr_reader :arguments

    def initialize(arguments)
      @arguments = arguments
    end
  end

  # Mirrors the real ActiveJob serialization stored in solid_queue_jobs.arguments:
  # the keyword args live in a single hash inside the top-level "arguments" array.
  def job_for(lesson_plan_id)
    FakeJob.new(
      "job_class" => "ProposeResourcesJob",
      "arguments" => [
        { "lesson_plan_id" => lesson_plan_id, "user_id" => 7, "source" => "x",
          "_aj_ruby2_keywords" => %w[lesson_plan_id user_id source] }
      ]
    )
  end

  test "matches a job whose serialized lesson_plan_id equals the target" do
    assert SolidQueueGenerationJobLookup.targets_lesson_plan?(job_for(42), 42)
    assert SolidQueueGenerationJobLookup.targets_lesson_plan?(job_for(42), "42")
  end

  test "does not match a job for a different lesson plan" do
    refute SolidQueueGenerationJobLookup.targets_lesson_plan?(job_for(99), 42)
  end

  test "does not match when arguments are malformed" do
    refute SolidQueueGenerationJobLookup.targets_lesson_plan?(FakeJob.new(nil), 42)
    refute SolidQueueGenerationJobLookup.targets_lesson_plan?(FakeJob.new("arguments" => []), 42)
  end
end
