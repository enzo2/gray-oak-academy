require "test_helper"

class EnrollmentsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @student = users(:student3)
    @course = courses(:one)
    @admin = users(:admin2)
  end

  test "admin enrolls student in a course" do
    sign_in @admin
    post enroll_admin_student_path(@student, course_id: @course.id)
    assert_redirected_to admin_student_path(@student)
    follow_redirect!
    assert_match @course.title, @response.body
  end

  test "admin unenrolls student from a course" do
    @student.enrollments.create!(course: @course)
    sign_in @admin
    delete unenroll_admin_student_path(@student, course_id: @course.id)
    assert_redirected_to admin_student_path(@student)
    follow_redirect!
    refute_match @course.title, @response.body
  end
end
