require "test_helper"

class GenerationStatusPartialTest < ActionView::TestCase
  def render_status(stage:, scope: nil, error: nil)
    lesson_plan = Struct.new(:generation_stage, :generation_error).new(stage, error)
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

  test "content scope surfaces failure with its error" do
    html = render_status(stage: "failed", error: "ChatGPT Plus usage limit reached")

    assert_includes html, "Generation failed."
    assert_includes html, "ChatGPT Plus usage limit reached"
  end

  test "resources scope does not echo the shared failure" do
    refute_includes render_status(stage: "failed", error: "boom", scope: :resources), "Generation failed."
  end
end
