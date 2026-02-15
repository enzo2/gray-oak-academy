require "test_helper"

class UndoCourseResearchChangesServiceTest < ActiveSupport::TestCase
  def setup
    @course = courses(:one)
    @course.update!(
      summary: "Initial summary",
      outline: [ { "Topic 1" => "Initial details" } ],
      outline_guidance_report_md: "Initial report",
      outline_research: { "source_anchors" => [] },
      course_prior_state: {}
    )
  end

  test "capture_prior_state stores one snapshot only" do
    service = UndoCourseResearchChangesService.new(course: @course)
    service.capture_prior_state!

    snapshot = @course.reload.course_prior_state
    assert_equal "Initial summary", snapshot["summary"]

    @course.update!(summary: "Mutated summary")
    service.capture_prior_state!

    assert_equal "Initial summary", @course.reload.course_prior_state["summary"]
  end

  test "undo restores snapshot and clears prior state" do
    service = UndoCourseResearchChangesService.new(course: @course)
    service.capture_prior_state!

    @course.update!(
      summary: "Changed summary",
      outline_guidance_report_md: "Changed report",
      outline_research_stage: "completed"
    )

    result = service.undo!
    assert_equal true, result[:ok]

    restored = @course.reload
    assert_equal "Initial summary", restored.summary
    assert_equal "Initial report", restored.outline_guidance_report_md
    assert_equal({}, restored.course_prior_state)
  end

  test "undo maps transient in-progress stage back to awaiting teacher input" do
    service = UndoCourseResearchChangesService.new(course: @course)
    @course.update!(
      outline_research_stage: "applying_guidance_updates",
      outline_guidance_questions: [ { "id" => "q1", "question" => "Question?" } ],
      outline_research: {
        "source_anchors" => [ { "id" => "anchor_1" } ]
      }
    )
    service.capture_prior_state!

    @course.update!(summary: "Mutated summary", outline_research_stage: "completed")

    result = service.undo!
    assert_equal true, result[:ok]
    assert_equal "awaiting_teacher_input", @course.reload.outline_research_stage
  end

  test "undo maps transient in-progress stage to idle when no review artifacts exist" do
    @course.update!(
      summary: "Changed summary",
      outline_research_stage: "completed",
      course_prior_state: {
        "summary" => "Initial summary",
        "outline" => [ { "Topic 1" => "Initial details" } ],
        "outline_guidance_report_md" => nil,
        "outline_guidance_questions" => [],
        "outline_guidance_answers" => {},
        "outline_research" => { "source_anchors" => [] },
        "outline_research_stage" => "applying_guidance_updates",
        "outline_research_error" => nil,
        "outline_research_run_id" => "run_123",
        "outline_research_response_id" => "resp_123"
      }
    )

    result = UndoCourseResearchChangesService.new(course: @course).undo!
    assert_equal true, result[:ok]

    restored = @course.reload
    assert_equal "idle", restored.outline_research_stage
    assert_equal "Initial summary", restored.summary
  end
end
