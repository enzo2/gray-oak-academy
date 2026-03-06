require "test_helper"

class Admin::StudentsControllerActionsTest < ActionDispatch::IntegrationTest
  def setup
    @admin = users(:admin)
    sign_in @admin
  end

  test "new_student action creates and adopts a student" do
    assert_difference("User.count", 1) do
      post new_admin_students_path, params: {
        user: {
          first_name: "New",
          last_name: "Student",
          email: "newstudent@example.com",
          password: "password",
          password_confirmation: "password",
          adopt_student: "1",
          signup_code: ENV["STUDENT_SIGNUP_CODE"]
        }
      }
    end

    new_student = User.find_by(email: "newstudent@example.com")
    assert_not_nil new_student
    assert_equal @admin, new_student.teacher
    assert_redirected_to admin_student_path(new_student)
  end

  test "new_student action creates a student without adopting" do
    assert_difference("User.count", 1) do
      post new_admin_students_path, params: {
        user: {
          first_name: "Another",
          last_name: "Student",
          email: "anotherstudent@example.com",
          password: "password",
          password_confirmation: "password",
          adopt_student: "0",
          signup_code: ENV["STUDENT_SIGNUP_CODE"]
        }
      }
    end

    another_student = User.find_by(email: "anotherstudent@example.com")
    assert_not_nil another_student
    assert_nil another_student.teacher
    assert_redirected_to admin_students_path
  end

  test "new_student action fails with invalid data" do
    assert_no_difference("User.count") do
      post new_admin_students_path, params: {
        user: {
          first_name: "",
          last_name: "Student",
          email: "invalid@example.com",
          password: "password",
          password_confirmation: "password",
          adopt_student: "1",
          signup_code: ENV["STUDENT_SIGNUP_CODE"]
        }
      }, as: :turbo_stream
    end

    assert_response :unprocessable_content
    assert_match /First name can&#39;t be blank/, response.body
  end

  test "adopt action assigns a teacher to a student" do
    student_without_teacher = User.create!(
      first_name: "Unadopted",
      last_name: "Student",
      email: "unadopted@example.com",
      password: "password",
      role: "student",
      signup_code: ENV["STUDENT_SIGNUP_CODE"]
    )
    assert_nil student_without_teacher.teacher

    post adopt_admin_student_path(student_without_teacher)

    assert_equal @admin, student_without_teacher.reload.teacher
    assert_redirected_to admin_student_path(student_without_teacher, active_tab: "active_courses")
  end

  test "unadopt action removes a teacher from a student" do
    student_with_teacher = users(:student)
    assert_equal @admin, student_with_teacher.teacher

    delete unadopt_admin_student_path(student_with_teacher)

    assert_nil student_with_teacher.reload.teacher
    assert_redirected_to admin_students_path
  end

  test "enroll action enrolls a student in a course" do
    student = users(:student)
    course_to_enroll = Course.create!(
      title: "Teacher-owned course",
      summary: "Available for enrollment",
      outline: [],
      grade_level: "2",
      teacher: @admin
    )

    assert_not student.courses.include?(course_to_enroll)

    post enroll_admin_student_path(student), params: { course_id: course_to_enroll.id }

    assert student.reload.courses.include?(course_to_enroll)
    assert_redirected_to admin_student_path(student, active_tab: :active_courses)
  end

  test "unenroll action removes a student from a course" do
    student = users(:student)
    course_to_unenroll = courses(:one) # A course the student is enrolled in

    assert student.courses.include?(course_to_unenroll)

    delete unenroll_admin_student_path(student), params: { course_id: course_to_unenroll.id }

    assert_not student.reload.courses.include?(course_to_unenroll)
    assert_redirected_to admin_student_path(student, active_tab: :active_courses)
  end
end
