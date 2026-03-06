require "test_helper"

class GenerateCourseReportJobTest < ActiveJob::TestCase
  test "perform creates student report for enrollment" do
    enrollment = enrollments(:one)

    fake_service = Object.new
    response = {
      "summary" => "Great student",
      "strengths" => [ "math" ],
      "areas_for_review" => [],
      "teaching_methods" => [ "examples" ]
    }

    fake_event_reporter = Object.new
    fake_event_reporter.define_singleton_method(:notify) { |_event| true }

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_service }) do
      LlmServiceRouting.stub(:complete_structured_output, response) do
        Rails.stub(:event, fake_event_reporter) do
          assert_difference "StudentReport.count", 1 do
            GenerateCourseReportJob.perform_now(enrollment)
          end
        end
      end
    end

    report = StudentReport.order(created_at: :desc).first
    assert_equal enrollment.id, report.reportable_id
    assert_equal "Enrollment", report.reportable_type
    assert_equal "ai_generated", report.author_type.to_s
    assert_equal "completed", report.status.to_s
  end
end
