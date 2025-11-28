require "test_helper"

class Admin::StudentsControllerTest < ActionDispatch::IntegrationTest
  test "adopt sets flash error when attempting to adopt self (validate_not_own_teacher)" do
    admin = users(:admin)
    sign_in admin

    # Sanity: admin shouldn't already have a teacher
    assert_nil admin.teacher

    post adopt_admin_student_path(admin.id)

    # Controller redirects with 422 on failure
    assert_response :unprocessable_content
    assert_equal admin_students_url, response.location

    # Flash should surface the model validation message
    assert flash[:error].present?, "Expected flash error to be set"
    assert_match(/cannot be yourself/i, flash[:error])

    # No change persisted
    assert_nil admin.reload.teacher
  end

  test "cannot view show page of another teacher's student" do
    teacher = users(:admin)
    other_student = users(:student2) # Belongs to admin2 or no one? Fixture says student2 has NO teacher or admin2?
    # Let's check fixture users.yml in my head/context
    # student2: teacher: nil? No, fixture says:
    # student2: ... teacher: nil (based on earlier dump, wait)
    # student2 fixture in dump:
    # student2:
    #   ...
    #   teacher: admin # Wait, student has teacher: admin.
    #   student2 has ... wait let me check the file content again.

    # In repomix-output.xml:
    # student: teacher: admin
    # student2: teacher: nil (implied? No, let's look at users.yml in dump)
    # student2: ... no teacher line.

    # So student2 has no teacher.
    # admin2 exists.

    sign_in teacher

    # Assign student2 to admin2
    other_teacher = users(:admin2)
    other_student.update!(teacher: other_teacher)

    get admin_student_path(other_student)
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "cannot enroll another teacher's student" do
    teacher = users(:admin)
    sign_in teacher

    other_teacher = users(:admin2)
    other_student = users(:student2)
    other_student.update!(teacher: other_teacher)

    course = courses(:one) # teacher's course

    post enroll_admin_student_path(other_student), params: { course_id: course.id }
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "cannot unenroll another teacher's student" do
    teacher = users(:admin)
    sign_in teacher

    other_teacher = users(:admin2)
    other_student = users(:student2)
    other_student.update!(teacher: other_teacher)

    # Student2 is already enrolled in course two (admin2's course) from fixtures
    course = courses(:two)

    delete unenroll_admin_student_path(other_student), params: { course_id: course.id }
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end
end
