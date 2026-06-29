require "test_helper"

class GenerationStatusPartialTest < ActionView::TestCase
  def render_status(stage:, scope: nil, error: nil, progress: nil)
    lesson_plan = Struct.new(:generation_stage, :generation_error).new(stage, error)
    lesson_plan.define_singleton_method(:resource_proposal_progress) { progress } if progress
    locals = { lesson_plan: lesson_plan }
    locals[:scope] = scope if scope
    render partial: "admin/lesson_plans/generation_status", locals: locals
  end

  test "content scope reports content generation" do
    assert_includes render_status(stage: "generating_content"), "Generating lesson plan content"
  end

  test "resources scope stays silent while content is generating" do
    html = render_status(stage: "generating_content", scope: :resources)

    refute_includes html, "Generating lesson plan content"
    assert_empty html.strip
  end

  test "resources scope reports only the proposal phase" do
    assert_includes render_status(stage: "proposing_resources", scope: :resources), "Proposing and validating resources"
  end

  test "resources scope shows proposal progress details when present" do
    html = render_status(
      stage: "proposing_resources",
      scope: :resources,
      progress: {
        "message" => "Running resource checks...",
        "detail" => "Turn 2: executing 3 tool calls.",
        "turn" => 2,
        "total_tool_calls" => 5
      }
    )

    assert_includes html, "Running resource checks"
    assert_includes html, "Turn 2: executing 3 tool calls."
  end

  test "content scope surfaces failure with its error" do
    html = render_status(stage: "failed", error: "ChatGPT Plus usage limit reached")

    assert_includes html, "Generation failed."
    assert_includes html, "ChatGPT Plus usage limit reached"
  end

  test "resources scope does not echo the shared failure" do
    refute_includes render_status(stage: "failed", error: "boom", scope: :resources), "Generation failed."
  end
end
