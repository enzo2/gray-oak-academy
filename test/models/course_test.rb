require "test_helper"

class CourseTest < ActiveSupport::TestCase
  def setup
    @course = courses(:one)
    @student = users(:one)
    @teacher = users(:two)
  end

  test "should be valid with valid attributes" do
    assert @course.valid?
  end

  test "should require a title" do
    @course.title = ""
    assert_not @course.valid?
  end

  test "should require a summary" do
    @course.summary = ""
    assert_not @course.valid?
  end

  test "should require a valid grade_level" do
    @course.grade_level = "!"
    assert_not @course.valid?
    @course.grade_level = "A"
    assert @course.valid?
    @course.grade_level = "10"
    assert @course.valid?
  end

  test "enrolled_in? returns true if student is enrolled" do
    assert @course.enrolled_in?(@student)
  end

  test "enrolled_in? returns false if student is not enrolled" do
    new_student = User.create!(first_name: "Test", last_name: "User", email: "testuser@example.com", password: "password", role: :student, signup_code: ENV["STUDENT_SIGNUP_CODE"])
    assert_not @course.enrolled_in?(new_student)
  end

  test "completed_by? returns false if enrollment is not completed" do
    assert_not @course.completed_by?(@student)
  end

  test "available_for_enrollment returns only courses not already enrolled" do
    available = Course.available_for_enrollment(@student, @course.teacher)
    assert_not_includes available, @course
  end
end
