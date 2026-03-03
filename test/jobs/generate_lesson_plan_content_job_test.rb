require "test_helper"

class GenerateLessonPlanContentJobTest < ActiveJob::TestCase
  test "concurrency controls scope to lesson plan id" do
    lesson_plan = Struct.new(:id).new(11)
    user = Struct.new(:id).new(2)

    assert_equal 1, GenerateLessonPlanContentJob.concurrency_limit
    assert_equal 10.minutes, GenerateLessonPlanContentJob.concurrency_duration
    assert_equal "lesson-plan-content-11", GenerateLessonPlanContentJob.concurrency_key.call(lesson_plan, user)
  end

  test "perform updates lesson_plan content and suggested_resources from parsed response" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan

    fake_service = Object.new
    fake_service.define_singleton_method(:complete) do |_messages, **_kwargs|
      {
        "lesson_plan" => [
          { "type" => "activity", "details" => "Warm up activity" },
          { "type" => "explain", "details" => "Explain concept" }
        ],
        "suggested_resources" => [
          { "type" => "book", "description" => "Reference book" }
        ]
      }
    end

    OpenaiApiService.stub(:new, ->(**_kwargs) { fake_service }) do
      Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
        assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
      end
    end

    lesson_plan.reload
    assert_equal "completed", lesson_plan.generation_stage
    assert_includes lesson_plan.content, { "activity" => "Warm up activity" }
    assert_includes lesson_plan.content, { "explain" => "Explain concept" }
    assert_equal [ { "book" => "Reference book" } ], lesson_plan.suggested_resources
  end
end
