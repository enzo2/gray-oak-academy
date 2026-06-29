require "test_helper"

class CourseTest < ActiveSupport::TestCase
  def setup
    @course = courses(:one)
    @student = users(:student)
    @teacher = users(:admin)
  end

  test "enrolled_in? returns true if student is enrolled" do
    assert @course.enrolled_in?(@student)
  end

  test "enrolled_in? returns false if student is not enrolled" do
    new_student = User.create!(first_name: "Test", last_name: "User", email: "testuser@example.com", password: "password", role: :student, signup_code: ENV["STUDENT_SIGNUP_CODE"])
    assert_not @course.enrolled_in?(new_student)
  end

  test "completed_by? returns false if enrollment is not completed" do
    assert_not @course.completed_by?(@student)
  end

  test "available_for_enrollment returns only courses not already enrolled" do
    available = Course.available_for_enrollment(@student, @course.teacher)
    assert_not_includes available, @course
  end

  test "kind scopes separate full courses from quick lessons" do
    quick_lesson = Course.create!(
      teacher: @teacher,
      title: "Quick Fractions",
      summary: "A quick one-off lesson about common denominators.",
      grade_level: "5",
      kind: "quick_lesson"
    )

    assert_includes Course.full_courses, @course
    assert_not_includes Course.full_courses, quick_lesson
    assert_includes Course.quick_lessons, quick_lesson
    assert_not_includes Course.quick_lessons, @course
  end

  test "available_for_enrollment excludes quick lessons" do
    quick_lesson = Course.create!(
      teacher: @teacher,
      title: "Quick Fractions",
      summary: "A quick one-off lesson about common denominators.",
      grade_level: "5",
      kind: "quick_lesson"
    )

    available = Course.available_for_enrollment(@student, @teacher)

    assert_not_includes available, quick_lesson
  end

  test "quick lesson course cannot have multiple lessons" do
    quick_lesson = Course.create!(
      teacher: @teacher,
      title: "Quick Fractions",
      summary: "A quick one-off lesson about common denominators.",
      grade_level: "5",
      kind: "quick_lesson"
    )
    quick_lesson.lessons.create!(
      title: "Common Denominators",
      goals: "Understand common denominators using shared units.",
      approx_duration_min: 20
    )

    second_lesson = quick_lesson.lessons.build(
      title: "Extra Practice",
      goals: "Practice using equivalent fractions.",
      approx_duration_min: 10
    )

    assert_not second_lesson.valid?
    assert_includes second_lesson.errors[:course], "quick lessons can only contain one lesson."
  end

  test "outline guidance questions are capped at five" do
    @course.outline_guidance_questions = [
      { "id" => "q1", "question" => "Q1" },
      { "id" => "q2", "question" => "Q2" },
      { "id" => "q3", "question" => "Q3" },
      { "id" => "q4", "question" => "Q4" },
      { "id" => "q5", "question" => "Q5" },
      { "id" => "q6", "question" => "Q6" }
    ]

    assert_not @course.valid?
    assert_includes @course.errors[:outline_guidance_questions], "must contain at most 5 questions."
  end

  test "unanswered_research_question_ids requires valid structured answers" do
    @course.update!(
      outline_guidance_questions: [
        { "id" => "q1", "question" => "First?" },
        { "id" => "q2", "question" => "Second?" },
        { "id" => "q3", "question" => "Third?" },
        { "id" => "q4", "question" => "Fourth?" }
      ],
      outline_guidance_answers: {
        "q1" => { "choice" => "A" },
        "q2" => { "choice" => "OTHER", "other_text" => "" },
        "q4" => "legacy free text"
      }
    )

    assert_equal [ "q2", "q3", "q4" ], @course.unanswered_research_question_ids
  end

  test "outline research progress is stored inside outline research payload" do
    @course.update!(
      outline_research: {
        "source_anchors" => [ { "id" => "anchor_1" } ]
      }
    )

    @course.update_outline_research_progress!(
      message: "Searching and synthesizing sources...",
      detail: "Exa deep-reasoning search is gathering evidence.",
      step: 2,
      total_steps: 4
    )

    @course.reload
    assert_equal "anchor_1", @course.outline_research.dig("source_anchors", 0, "id")
    assert_equal "Searching and synthesizing sources...", @course.outline_research_progress_message
    assert_equal 2, @course.outline_research_progress["step"]
    assert_equal 4, @course.outline_research_progress["total_steps"]
  end

  test "outline research report predicates reflect availability of review page" do
    @course.update!(
      outline_research_stage: "completed",
      outline_guidance_report_md: nil
    )

    assert_equal false, @course.outline_guidance_report_present?
    assert_equal false, @course.outline_research_review_page_available?

    @course.update!(outline_guidance_report_md: "## Guidance")
    assert_equal true, @course.outline_guidance_report_present?
    assert_equal true, @course.outline_research_review_page_available?

    @course.update!(outline_research_stage: "awaiting_teacher_input", outline_guidance_report_md: nil)
    assert_equal true, @course.outline_research_review_page_available?
  end

  test "normalizes escaped markdown newlines in guidance report" do
    escaped_report = "# Guidance\\n\\n## Applied Preferences\\n- Keep structure\\n- Add cases"

    @course.update!(outline_guidance_report_md: escaped_report)

    assert_equal "# Guidance\n\n## Applied Preferences\n- Keep structure\n- Add cases", @course.reload.outline_guidance_report_md
  end

  test "outline research restart and resume predicates reflect failed run state" do
    @course.update!(
      outline_research_stage: "failed",
      outline_research_response_id: nil
    )

    assert_equal false, @course.outline_research_resumable_run?
    assert_equal false, @course.outline_research_restart_blocked?

    @course.update!(outline_research_response_id: "resp_123")
    assert_equal true, @course.outline_research_resumable_run?
    assert_equal true, @course.outline_research_restart_blocked?
  end

  test "reset_outline_research! clears research artifacts and keeps core course fields" do
    original_title = @course.title
    original_summary = @course.summary
    original_outline = @course.outline

    @course.update!(
      outline_research_stage: "failed",
      outline_research_error: "Some error",
      outline_research: { "source_anchors" => [ { "id" => "a1" } ] },
      outline_guidance_report_md: "## Guidance",
      outline_guidance_questions: [ { "id" => "q1", "question" => "Question?" } ],
      outline_guidance_answers: { "q1" => { "choice" => "B" }, "_additional_comments" => "Please adjust pacing." },
      outline_research_run_id: "run_123",
      outline_research_response_id: "resp_123",
      course_prior_state: { "summary" => "old summary" }
    )

    @course.reset_outline_research!
    @course.reload

    assert_equal "idle", @course.outline_research_stage
    assert_nil @course.outline_research_error
    assert_equal({}, @course.outline_research)
    assert_nil @course.outline_guidance_report_md
    assert_equal [], @course.outline_guidance_questions
    assert_equal({}, @course.outline_guidance_answers)
    assert_nil @course.outline_research_run_id
    assert_nil @course.outline_research_response_id
    assert_equal({}, @course.course_prior_state)

    assert_equal original_title, @course.title
    assert_equal original_summary, @course.summary
    assert_equal original_outline, @course.outline
  end
end
