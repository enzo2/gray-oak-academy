require "test_helper"

class LessonPlanTest < ActiveSupport::TestCase
  test "cannot publish while linked resources are pending approval" do
    lesson_plan = lesson_plans(:one)
    lesson_plan.content = [ { "Intro" => "Ready" } ]

    pending_resource = Resource.create!(
      teacher: users(:admin),
      category: "Web Resource",
      description: "Pending URL",
      uri: "https://example.com/pending",
      approved: false
    )
    lesson_plan.resources << pending_resource

    lesson_plan.status = "published"
    assert_not lesson_plan.valid?
    assert_includes lesson_plan.errors[:status], "cannot be published while linked resources are pending approval."
  end

  test "generation helper methods reflect stage" do
    lesson_plan = lesson_plans(:one)

    lesson_plan.generation_stage = "idle"
    assert_not lesson_plan.generation_in_progress?
    assert_not lesson_plan.initial_generation_completed?

    lesson_plan.generation_stage = "generating_content"
    assert lesson_plan.generation_in_progress?
    assert lesson_plan.initial_generation_completed?
  end
end
