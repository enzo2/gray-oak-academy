require "test_helper"

class EnrollmentTest < ActiveSupport::TestCase
  def setup
    @enrollment = enrollments(:one)
    @student = users(:student)
    @course = courses(:one)
  end

  test "should be valid with valid attributes" do
    assert @enrollment.valid?
  end

  test "completed_lessons returns correct lessons" do
    # No completed lessons in fixture, so should be empty
    assert_equal [], @enrollment.completed_lessons
  end

  test "incomplete_lessons returns all lessons if none completed" do
    assert_equal @course.lessons.sort_by(&:position), @enrollment.incomplete_lessons.sort_by(&:position)
  end

  test "progress_percentage is 0 if no lessons completed" do
    assert_equal 0, @enrollment.progress_percentage
  end

  test "total_lessons_count returns correct count" do
    assert_equal @course.lessons.count, @enrollment.total_lessons_count
  end

  test "completed? returns false if not all lessons completed" do
    assert_not @enrollment.completed?
  end
end
