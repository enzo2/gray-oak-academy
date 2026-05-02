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

  test "validate_signup_role rejects superuser during sign up" do
    superuser = User.new(
      first_name: "Test",
      last_name: "Superuser",
      email: "testsuperuser@example.com",
      password: "password",
      role: "superuser",
      signup_code: ENV["TEACHER_SIGNUP_CODE"]
    )

    assert_not superuser.valid?
    assert_includes superuser.errors[:role], "must be student or admin during sign up"
  end

  test "should not destroy user with associated courses" do
    assert @admin.taught_courses.any?

    assert_no_difference("User.count") do
      assert_not @admin.destroy
    end
    assert_includes @admin.errors[:base], "Cannot delete user. Please transfer owned courses to another teacher first."
  end

  test "should destroy user without associated courses" do
    assert_empty @student.taught_courses

    assert_difference("User.count", -1) do
      @student.destroy
    end
  end

  test "should destroy teacher without courses and orphan adopted students" do
    teacher = User.create!(
      first_name: "Delete",
      last_name: "Me",
      email: "delete-me-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: "admin",
      signup_code: ENV["TEACHER_SIGNUP_CODE"]
    )

    @student2.update!(teacher: teacher)

    assert_difference("User.count", -1) do
      teacher.destroy
    end

    assert_nil @student2.reload.teacher_id
  end

  test "should not destroy teacher with resource-linked applets" do
    teacher = User.create!(
      first_name: "Applet",
      last_name: "Owner",
      email: "applet-owner-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: "admin",
      signup_code: ENV["TEACHER_SIGNUP_CODE"]
    )

    standalone_applet = Applet.create!(title: "Standalone", code: "console.log('standalone')", user: teacher)
    resource_applet = Applet.create!(title: "Linked", code: "console.log('linked')", user: teacher)
    Resource.create!(teacher: teacher, category: "Applet", description: "Linked resource", applet: resource_applet)

    assert_no_difference("User.count") do
      assert_not teacher.destroy
    end

    assert Applet.exists?(standalone_applet.id)
    assert Applet.exists?(resource_applet.id)
    assert_includes teacher.errors[:base], "Cannot delete user. Please transfer resource-linked applets to another teacher first."
  end
end
