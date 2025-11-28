require "test_helper"

class GenerateObservationsJobTest < ActiveJob::TestCase
  def setup
    @student = users(:student)
    @lesson_progress = lesson_progresses(:one)

    # Create a lesson report
    @report = StudentReport.create!(
      student: @student,
      reportable: @lesson_progress,
      progress_data: { summary: "Good lesson" },
      status: :completed,
      author_type: :ai_generated
    )

    # Ensure "generate_observations" prompt exists
    Prompt.find_or_create_by!(
      category: "generate_observations",
      teacher: nil,
      title: "Generate Observations",
      prompt: "Review the following student report: {lesson_report}"
    )
  end

  test "generates pending observations from LLM response" do
    # Stub OpenaiApiService to return observations
    mock_service = Minitest::Mock.new
    response = { "observations" => [ "Obs 1", "Obs 2" ] }

    mock_service.expect :complete, response do |messages, response_format:, schema:, prefill:|
      true # Accepting any args for simplicity, or check schema if needed
    end

    OpenaiApiService.stub :new, mock_service do
      assert_difference("Observation.count", 2) do
        GenerateObservationsJob.perform_now(@report)
      end
    end

    obs = Observation.order(created_at: :desc).limit(2)
    assert_equal "Obs 2", obs.first.content
    assert_equal "pending", obs.first.status
    assert_equal @student, obs.first.student
    assert_equal @lesson_progress, obs.first.source

    assert_equal "Obs 1", obs.second.content
    assert_equal "pending", obs.second.status
  end

  test "does not generate observations for non-LessonProgress reports" do
    @report.update!(reportable: enrollments(:one))

    assert_no_difference("Observation.count") do
      GenerateObservationsJob.perform_now(@report)
    end
  end
end
