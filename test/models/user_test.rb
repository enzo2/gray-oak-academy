require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @admin = users(:admin)
    @admin2 = users(:admin2)
    @student = users(:student)
    @student2 = users(:student2)
  end

  test "validate_teacher_role: teacher cannot be a student" do
    # Attempt to assign a student as the teacher of another user
    @student2.teacher = @student

    assert_not @student2.valid?, "User should be invalid when teacher is a student"
    assert_includes @student2.errors[:teacher], "cannot be a student."
  end

  test "validate_teacher_role: teacher can be an admin" do
    # Assign an admin as the teacher (valid)
    @student2.teacher = @admin

    assert @student2.valid?, @student2.errors.full_messages.to_sentence
  end

  test "validate_not_own_teacher: user cannot set themselves as their own teacher" do
    # Admin tries to set themselves as their own teacher (invalid)
    @admin.teacher = @admin

    assert_not @admin.valid?, "User should be invalid when teacher is themselves"
    assert_includes @admin.errors[:teacher], "cannot be yourself"
  end

  test "validate_signup_code: requires a valid signup code for new users" do
    # Test student signup
    student = User.new(
      first_name: "Test",
      last_name: "Student",
      email: "teststudent@example.com",
      password: "password",
      role: "student",
      signup_code: ENV["STUDENT_SIGNUP_CODE"]
    )
    assert student.valid?

    student.signup_code = "invalid"
    assert_not student.valid?
    assert_includes student.errors[:signup_code], "is invalid"

    # Test teacher signup
    teacher = User.new(
      first_name: "Test",
      last_name: "Teacher",
      email: "testteacher@example.com",
      password: "password",
      role: "admin",
      signup_code: ENV["TEACHER_SIGNUP_CODE"]
    )
    assert teacher.valid?

    teacher.signup_code = "invalid"
    assert_not teacher.valid?
    assert_includes teacher.errors[:signup_code], "is invalid"
  end
end
