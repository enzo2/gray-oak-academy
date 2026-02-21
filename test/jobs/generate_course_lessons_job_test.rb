require "test_helper"

class GenerateCourseLessonsJobTest < ActiveJob::TestCase
  test "job limits concurrency per course" do
    course = Struct.new(:id).new(24)
    user = Struct.new(:id).new(9)

    assert_equal 1, GenerateCourseLessonsJob.concurrency_limit
    assert_equal 10.minutes, GenerateCourseLessonsJob.concurrency_duration
    assert_equal "generate-course-lessons-24", GenerateCourseLessonsJob.concurrency_key.call(course, user)
  end
end
