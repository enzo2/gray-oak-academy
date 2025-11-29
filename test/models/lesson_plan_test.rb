require "test_helper"

class LessonPlanTest < ActiveSupport::TestCase
  test "teacher association works through course" do
    lesson_plan = lesson_plans(:one)
    assert_equal users(:admin), lesson_plan.teacher
  end
end
