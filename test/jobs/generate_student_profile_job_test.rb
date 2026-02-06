require "test_helper"

class GenerateStudentProfileJobTest < ActiveJob::TestCase
  def setup
    @student = users(:student)
    @teacher = users(:admin)

    # Ensure student has a teacher
    @student.update!(teacher: @teacher)
  end

  test "generates student profile from LLM response" do
    mock_service = Minitest::Mock.new
    response = {
      "current_snapshot" => "Student shows strong progress in recent lessons.",
      "learning_patterns" => [ "Visual learner", "Benefits from hands-on activities" ],
      "current_strengths" => [ "Mathematical reasoning", "Creative problem-solving" ],
      "areas_for_focus" => [ "Reading comprehension" ],
      "effective_approaches" => [ "Interactive applets", "Real-world examples" ],
      "approaches_to_avoid" => [ "Long lectures without breaks" ],
      "recommendations" => [ "Continue with visual aids", "Incorporate more reading exercises" ]
    }

    mock_service.expect :complete, response do |messages, response_format:, schema:, prefill:|
      true
    end

    OpenaiApiService.stub :new, ->(*, **) { mock_service } do
      assert_difference("StudentReport.count", 1) do
        assert_difference("Notification.count", 1) do
          GenerateStudentProfileJob.perform_now(@student)
        end
      end
    end

    report = StudentReport.order(created_at: :desc).first
    assert_equal "User", report.reportable_type
    assert_equal @student.id, report.reportable_id
    assert_equal @student, report.student
    assert_equal @teacher, report.teacher
    assert_equal "ai_generated", report.author_type
    assert_equal "completed", report.status
    assert_equal "Student shows strong progress in recent lessons.", report.progress_data["current_snapshot"]
    assert_includes report.progress_data["learning_patterns"], "Visual learner"

    md = report.to_markdown
    assert_operator md.index("**Current snapshot**"), :<, md.index("**Learning patterns**")
    assert_operator md.index("**Learning patterns**"), :<, md.index("**Current strengths**")
    assert_operator md.index("**Current strengths**"), :<, md.index("**Areas for focus**")
    assert_operator md.index("**Areas for focus**"), :<, md.index("**Effective approaches**")
    assert_operator md.index("**Effective approaches**"), :<, md.index("**Approaches to avoid**")
    assert_operator md.index("**Approaches to avoid**"), :<, md.index("**Recommendations**")

    notification = Notification.order(created_at: :desc).first
    assert_equal "student.profile_generated", notification.event_type
    assert_equal response["current_snapshot"], notification.params["current_snapshot"]
  end

  test "does not generate profile for orphaned students" do
    @student.update_column(:teacher_id, nil)
    @student.reload

    assert_no_difference("StudentReport.count") do
      GenerateStudentProfileJob.perform_now(@student)
    end
  end

  test "includes previous profile date in prompt" do
    # Create a previous profile report
    previous_report = StudentReport.create!(
      student: @student,
      teacher: @teacher,
      reportable: @student,
      progress_data: { "current_snapshot" => "Previous snapshot" },
      author_type: :ai_generated,
      status: :completed,
      created_at: 1.week.ago
    )

    mock_service = Minitest::Mock.new
    response = {
      "current_snapshot" => "Updated snapshot",
      "learning_patterns" => [],
      "current_strengths" => [],
      "areas_for_focus" => [],
      "effective_approaches" => [],
      "approaches_to_avoid" => [],
      "recommendations" => []
    }

    prompt_checked = false
    mock_service.expect :complete, response do |messages, response_format:, schema:, prefill:|
      # Verify prompt contains previous profile date
      prompt_checked = messages.first[:content].include?(previous_report.created_at.strftime("%B %d, %Y"))
      true
    end

    OpenaiApiService.stub :new, ->(*, **) { mock_service } do
      @student.reload
      GenerateStudentProfileJob.perform_now(@student)
    end

    assert prompt_checked, "Prompt should include previous profile date"
  end

  test "profile_reports scope returns only User reportable types" do
    # Create a profile report
    profile_report = StudentReport.create!(
      student: @student,
      teacher: @teacher,
      reportable: @student,
      progress_data: { "current_snapshot" => "Test" },
      author_type: :ai_generated,
      status: :completed
    )

    # Create a lesson report for contrast
    lesson_report = StudentReport.create!(
      student: @student,
      teacher: @teacher,
      reportable: lesson_progresses(:one),
      progress_data: { "summary" => "Test" },
      author_type: :ai_generated,
      status: :completed
    )

    profile_reports = StudentReport.profile_reports
    assert_includes profile_reports, profile_report
    assert_not_includes profile_reports, lesson_report
  end
end
