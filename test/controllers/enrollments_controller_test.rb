require "test_helper"

class EnrollmentsControllerTest < ActionDispatch::IntegrationTest
  test "show responds to html" do
    sign_in users(:admin)
    enrollment = enrollments(:one)

    get enrollment_path(enrollment)

    assert_response :success
    assert_match enrollment.course.title, response.body
    assert_match "Back to Student Dashboard", response.body
  end

  test "teacher sees inline edit controls for lesson reports" do
    teacher = users(:admin)
    report = create_lesson_report(lesson_progresses(:one))
    sign_in teacher

    get enrollment_path(enrollments(:one))

    assert_response :success
    assert_select "turbo-frame#editable_student_report_#{report.id}"
    assert_select "a[href='#{edit_admin_student_report_path(report, context: "enrollment")}']", text: /Edit/
  end

  test "teacher sees inline edit controls for a completed course report" do
    teacher = users(:admin)
    student = users(:student)
    enrollment = enrollments(:one)
    create_lesson_report(lesson_progresses(:one))
    create_lesson_report(lesson_progresses(:audio_only_progress))
    course_report = StudentReport.create!(
      student: student,
      teacher: teacher,
      reportable: enrollment,
      progress_data: { "summary" => "Completed the course" },
      author_type: :ai_generated,
      status: :completed
    )
    sign_in teacher

    get enrollment_path(enrollment)

    assert_response :success
    assert_select "h3", text: "Course report"
    assert_select "turbo-frame#editable_student_report_#{course_report.id}"
    assert_select "a[href='#{edit_admin_student_report_path(course_report, context: "enrollment")}']", text: /Edit/
  end

  test "student sees reports without edit controls" do
    report = create_lesson_report(lesson_progresses(:one))
    sign_in users(:student)

    get enrollment_path(enrollments(:one))

    assert_response :success
    assert_select "turbo-frame#editable_student_report_#{report.id}"
    assert_select "a[href^='#{edit_admin_student_report_path(report)}']", count: 0
  end

  test "show responds to turbo stream" do
    sign_in users(:admin)
    enrollment = enrollments(:one)

    get enrollment_path(enrollment), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match 'action="visit"', response.body
  end

  test "show for student includes dashboard back link preserving active tab" do
    sign_in users(:student)
    enrollment = enrollments(:one)

    get enrollment_path(enrollment, active_tab: :past_courses)

    assert_response :success
    assert_match "Back to Dashboard", response.body
    assert_match %r{/student/dashboard\?active_tab=past_courses}, response.body
  end

  test "teacher cannot view another teacher enrollment" do
    sign_in users(:admin2)

    get enrollment_path(enrollments(:one))

    assert_response :not_found
  end

  test "student cannot view another students enrollment" do
    sign_in users(:student2)

    get enrollment_path(enrollments(:one))

    assert_response :not_found
  end

  test "teacher can view own enrollment from my lessons" do
    teacher = users(:admin)
    course = Course.create!(
      title: "Teacher Self Study",
      summary: "Course for teacher self enrollment",
      outline: [],
      grade_level: "1",
      teacher: teacher
    )
    enrollment = Enrollment.create!(student: teacher, course: course)
    sign_in teacher

    get enrollment_path(enrollment)

    assert_response :success
    assert_match course.title, response.body
  end

  private

  def create_lesson_report(lesson_progress)
    StudentReport.create!(
      student: lesson_progress.student,
      teacher: lesson_progress.lesson.teacher,
      reportable: lesson_progress,
      progress_data: { "summary" => "Completed lesson" },
      author_type: :ai_generated,
      status: :completed
    )
  end
end
