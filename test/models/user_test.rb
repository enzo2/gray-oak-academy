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
end
