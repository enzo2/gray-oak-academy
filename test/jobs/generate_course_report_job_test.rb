require "test_helper"

class GenerateCourseReportJobTest < ActiveJob::TestCase
  test "perform creates student report for enrollment" do
    enrollment = enrollments(:one)

    fake_service = Object.new
    fake_service.define_singleton_method(:complete) do |_messages, **_kwargs|
      {
        "summary" => "Great student",
        "strengths" => [ "math" ],
        "areas_for_review" => [],
        "teaching_methods" => [ "examples" ]
      }
    end

    fake_event_reporter = Object.new
    fake_event_reporter.define_singleton_method(:notify) { |_event| true }

    OpenaiApiService.stub(:new, ->(**_kwargs) { fake_service }) do
      Rails.stub(:event, fake_event_reporter) do
        assert_difference "StudentReport.count", 1 do
          GenerateCourseReportJob.perform_now(enrollment)
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
