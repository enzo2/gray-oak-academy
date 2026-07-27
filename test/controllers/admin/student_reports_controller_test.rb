require "test_helper"

class Admin::StudentReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:admin)
    @student = users(:student)
    @report = student_reports(:LessonReport1)
  end

  test "teacher opens a structured inline editor" do
    sign_in @teacher

    get edit_admin_student_report_path(@report, context: "journal")

    assert_response :success
    assert_select "turbo-frame#editable_student_report_#{@report.id}"
    assert_select "textarea[name='student_report[report_fields][summary]']", text: "Did well"
    assert_select "textarea[name='student_report[report_fields][strengths]']"
    assert_select "input[name='context'][value='journal']"
    assert_match "Existing memories and observations are not automatically regenerated", response.body
  end

  test "course report editor uses course sections" do
    course_report = StudentReport.create!(
      student: @student,
      teacher: @teacher,
      reportable: enrollments(:one),
      progress_data: { "summary" => "Course summary", "strengths" => [ "Addition" ] },
      author_type: :ai_generated,
      status: :completed
    )
    sign_in @teacher

    get edit_admin_student_report_path(course_report, context: "enrollment")

    assert_response :success
    assert_select "h3", text: "Edit course report"
    assert_select "textarea[name='student_report[report_fields][summary]']", text: "Course summary"
    assert_select "textarea[name='student_report[report_fields][other_observations]']"
    assert_select "textarea[name='student_report[report_fields][memories]']", count: 0
  end

  test "teacher correction updates report data and provenance via turbo stream" do
    sign_in @teacher

    patch admin_student_report_path(@report),
          params: {
            context: "enrollment",
            student_report: {
              report_fields: {
                summary: "Teacher-corrected summary",
                strengths: "Careful reasoning\nClear explanation",
                areas_for_review: "Practice regrouping"
              }
            }
          },
          as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='editable_student_report_#{@report.id}']"
    assert_match "corrected by Admin User", response.body

    @report.reload
    assert_equal "Teacher-corrected summary", @report.progress_data["summary"]
    assert_equal [ "Careful reasoning", "Clear explanation" ], @report.progress_data["strengths"]
    assert_equal [ "Practice regrouping" ], @report.progress_data["areas_for_review"]
    assert_equal @teacher, @report.edited_by
    assert_not_nil @report.edited_at
    assert @report.author_type_ai_generated?
  end

  test "teacher receives inline validation errors" do
    sign_in @teacher
    @report.update!(progress_data: @report.progress_data.merge("evidence" => { "score" => 3 }))

    patch admin_student_report_path(@report),
          params: {
            student_report: { report_fields: { evidence: "invalid json" } }
          },
          as: :turbo_stream

    assert_response :unprocessable_content
    assert_select "turbo-stream[action='replace'][target='editable_student_report_#{@report.id}']"
    assert_match "Evidence must contain valid JSON", response.body
    assert_match "invalid json", response.body
  end

  test "another teacher cannot edit the report" do
    sign_in users(:admin2)

    get edit_admin_student_report_path(@report)

    assert_response :not_found
  end

  test "students cannot access report editing" do
    sign_in @student

    get edit_admin_student_report_path(@report)

    assert_redirected_to student_root_path
  end

  test "student profiles are not editable through this workflow" do
    profile = StudentReport.create!(
      student: @student,
      teacher: @teacher,
      reportable: @student,
      progress_data: { "current_snapshot" => "Profile" },
      author_type: :ai_generated,
      status: :completed
    )
    sign_in @teacher

    get edit_admin_student_report_path(profile)

    assert_response :not_found
  end
end
