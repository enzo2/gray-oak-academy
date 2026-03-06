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
    response = {
      "lesson_plan" => [
        { "type" => "activity", "details" => "Warm up activity" },
        { "type" => "explain", "details" => "Explain concept" }
      ],
      "suggested_resources" => [
        { "type" => "book", "description" => "Reference book" }
      ]
    }

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_service }) do
      LlmServiceRouting.stub(:complete_structured_output, response) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          assert GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
        end
      end
    end

    lesson_plan.reload
    assert_equal "completed", lesson_plan.generation_stage
    assert_includes lesson_plan.content, { "activity" => "Warm up activity" }
    assert_includes lesson_plan.content, { "explain" => "Explain concept" }
    assert_equal [ { "book" => "Reference book" } ], lesson_plan.suggested_resources
  end

  test "perform appends steering guidance to prompt when provided" do
    teacher = users(:admin)
    lesson_plan = lessons(:one).lesson_plan
    captured_messages = nil

    fake_service = Object.new
    response = {
      "lesson_plan" => [
        { "type" => "activity", "details" => "Warm up activity" }
      ],
      "suggested_resources" => []
    }

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_service }) do
      LlmServiceRouting.stub(:complete_structured_output, ->(**kwargs) {
        captured_messages = kwargs[:messages]
        response
      }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          assert GenerateLessonPlanContentJob.perform_now(
            lesson_plan,
            teacher,
            steering_guidance: "Prefer a walk-and-talk discussion with minimal chalkboard use."
          )
        end
      end
    end

    assert_includes captured_messages.first[:content], "Additional steering from the supervising teacher for this run:"
    assert_includes captured_messages.first[:content], "Prefer a walk-and-talk discussion with minimal chalkboard use."
  end
end
