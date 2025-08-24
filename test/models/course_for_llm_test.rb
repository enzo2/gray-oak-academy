require "test_helper"

class CourseForLlmTest < ActiveSupport::TestCase
  setup do
    @course = courses(:one)
  end

  test "for_llm returns expected keys and lesson ordering" do
    payload = ActiveSupport::HashWithIndifferentAccess.new(@course.for_llm)
    assert payload["id"], "expected id"
    assert payload["title"], "expected title"
    assert payload["summary"], "expected summary"
    assert payload["grade_level"], "expected grade_level"
    assert payload["status"], "expected status"
    assert payload["outline"], "expected outline"
    assert payload["lessons"], "expected lessons"

    lessons = payload["lessons"]
    assert lessons.is_a?(Array)
    # Ensure lessons are ordered by position ascending
    positions = lessons.map { |l| l.with_indifferent_access["position"] }
    assert_equal positions.sort, positions
  end
end
