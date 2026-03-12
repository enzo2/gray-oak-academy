require "test_helper"

class LessonPlanTest < ActiveSupport::TestCase
  test "new lesson plans only auto-link include-by-default resources from the owning teacher" do
    teacher = users(:admin)
    other_teacher = users(:admin2)
    teacher_default = Resource.create!(
      teacher: teacher,
      category: "Book",
      description: "Teacher default",
      include_by_default: true
    )
    other_teacher_default = Resource.create!(
      teacher: other_teacher,
      category: "Book",
      description: "Other teacher default",
      include_by_default: true
    )
    lesson = Lesson.create!(
      title: "Fresh lesson",
      goals: "Practice scoping default resources correctly.",
      approx_duration_min: 30,
      course: courses(:one),
      position: 99
    )

    lesson_plan = lesson.build_lesson_plan

    assert_includes lesson_plan.resources, teacher_default
    assert_not_includes lesson_plan.resources, other_teacher_default
  end

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
