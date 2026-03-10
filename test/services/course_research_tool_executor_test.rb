require "test_helper"

class CourseResearchToolExecutorTest < ActiveSupport::TestCase
  def setup
    @teacher = users(:admin)
    @course = courses(:one)
    @course.update!(
      summary: "Original summary",
      outline: [ { "Topic 1" => "Original details" } ],
      outline_guidance_report_md: "Original report",
      outline_research: {
        "source_anchors" => [
          { "id" => "anchor_1", "title" => "Old", "url" => "https://example.com/old", "excerpt" => "", "highlights" => [], "notes" => "" }
        ],
        "coverage_gaps" => [ "Gap A" ],
        "factual_notes" => [],
        "alternative_approaches" => []
      },
      course_prior_state: {}
    )
  end

  test "apply_course_research_update overwrites fields and captures snapshot once" do
    executor = CourseResearchToolExecutor.new(course: @course, current_user: @teacher)

    result = executor.execute(
      "id" => "call_apply_1",
      "name" => "apply_course_research_update",
      "arguments" => {
        summary: "Updated summary",
        outline: [
          { topic: "New Topic", description: "New details" }
        ],
        outline_guidance_report_md: "Updated report",
        outline_research: {
          "source_anchors" => [
            { "id" => "anchor_new", "title" => "New source", "url" => "https://example.com/new", "excerpt" => "Excerpt", "highlights" => [ "Point A" ], "notes" => "Keep" }
          ],
          "coverage_gaps" => [ "Gap B" ],
          "factual_notes" => [ "Note 1" ],
          "alternative_approaches" => [ "Approach 1" ]
        }
      }.to_json
    )

    assert_equal "function_call_output", result[:type]
    payload = JSON.parse(result[:output])
    assert_equal "Updated summary", payload.dig("course", "summary")
    assert_equal [ { "New Topic" => "New details" } ], payload.dig("course", "outline")

    course = @course.reload
    assert_equal "Updated summary", course.summary
    assert_equal "Updated report", course.outline_guidance_report_md
    assert_equal "anchor_new", course.outline_research.dig("source_anchors", 0, "id")
    assert_equal "Original summary", course.course_prior_state["summary"]

    executor.execute(
      "id" => "call_apply_2",
      "name" => "apply_course_research_update",
      "arguments" => {
        summary: "Updated summary again",
        outline: [
          { topic: "New Topic", description: "New details" }
        ],
        outline_guidance_report_md: "Updated report again",
        outline_research: course.outline_research
      }.to_json
    )

    assert_equal "Original summary", @course.reload.course_prior_state["summary"]
  end

  test "update_outline_research merges patch and normalizes anchors" do
    executor = CourseResearchToolExecutor.new(course: @course, current_user: @teacher)

    result = executor.execute(
      "id" => "call_patch_1",
      "name" => "update_outline_research",
      "arguments" => {
        outline_research_patch: {
          "source_anchors" => [
            { "id" => "anchor_1", "title" => "Old", "url" => "https://example.com/old", "excerpt" => "", "highlights" => [], "notes" => "" }
          ],
          "factual_notes" => [ "Updated note" ]
        }
      }.to_json
    )

    assert_equal "function_call_output", result[:type]
    payload = JSON.parse(result[:output])
    assert_equal "anchor_1", payload.dig("course", "outline_research", "source_anchors", 0, "id")
    assert_equal [ "Updated note" ], payload.dig("course", "outline_research", "factual_notes")
  end

  test "update_outline_research ignores null placeholders in patch" do
    executor = CourseResearchToolExecutor.new(course: @course, current_user: @teacher)

    result = executor.execute(
      "id" => "call_patch_2",
      "name" => "update_outline_research",
      "arguments" => {
        outline_research_patch: {
          "source_anchors" => nil,
          "coverage_gaps" => nil,
          "factual_notes" => [ "Only this should change" ]
        }
      }.to_json
    )

    assert_equal "function_call_output", result[:type]
    payload = JSON.parse(result[:output])
    assert_equal [ "Only this should change" ], payload.dig("course", "outline_research", "factual_notes")
    assert_equal 1, payload.dig("course", "outline_research", "source_anchors").size
  end

  test "tool schemas define strict outline_research objects" do
    executor = CourseResearchToolExecutor.new(course: @course, current_user: @teacher)

    apply_tool = executor.send(:apply_course_research_update_tool)
    apply_schema = executor.send(:apply_course_research_update_tool)
      .dig(:parameters)
    assert_equal %w[summary outline outline_guidance_report_md outline_research], apply_schema[:required]
    assert_includes apply_tool[:description], "pass null"

    outline_research_schema = apply_schema
      .dig(:properties, :outline_research)
    assert_equal [ "object", "null" ], outline_research_schema[:type]
    assert_equal false, outline_research_schema[:additionalProperties]
    assert_equal %w[source_anchors coverage_gaps factual_notes alternative_approaches], outline_research_schema[:required]
    assert_equal false, outline_research_schema.dig(:properties, :source_anchors, :items, :additionalProperties)
    assert_equal %w[id title url excerpt highlights notes], outline_research_schema.dig(:properties, :source_anchors, :items, :required)
    assert_includes outline_research_schema[:description], "markdown"
    assert_includes outline_research_schema.dig(:properties, :coverage_gaps, :description), "leave unchanged"
    assert_includes outline_research_schema.dig(:properties, :source_anchors, :items, :properties, :notes, :description), "Markdown"

    patch_schema = executor.send(:update_outline_research_tool)
      .dig(:parameters, :properties, :outline_research_patch)
    assert_equal "object", patch_schema[:type]
    assert_equal false, patch_schema[:additionalProperties]
    assert_equal false, patch_schema.dig(:properties, :source_anchors, :items, :additionalProperties)
  end
end
