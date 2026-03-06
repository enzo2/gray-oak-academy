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
    response = { "observations" => [ "Obs 1", "Obs 2" ] }

    LlmServiceRouting.stub(:build_completion_client, Object.new) do
      LlmServiceRouting.stub(:complete_structured_output, response) do
      assert_difference("Observation.count", 2) do
        GenerateObservationsJob.perform_now(@report)
      end
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

  test "handles missing reportable gracefully" do
    # Simulate orphaned report
    @report.update_column(:reportable_id, nil)

    assert_no_difference("Observation.count") do
      GenerateObservationsJob.perform_now(@report)
    end
  end

  test "fires notification on observation generation" do
    response = { "observations" => [ "Obs 1" ] }

    LlmServiceRouting.stub(:build_completion_client, Object.new) do
      LlmServiceRouting.stub(:complete_structured_output, response) do
      assert_difference -> { Notification.count }, 1 do
        GenerateObservationsJob.perform_now(@report)
      end
      end
    end

    notification = Notification.order(created_at: :desc).first
    assert_equal "observation.generated", notification.event_type
    assert_equal users(:admin), notification.recipient
    assert_includes notification.message, "1 new pending observation"
  end
end
