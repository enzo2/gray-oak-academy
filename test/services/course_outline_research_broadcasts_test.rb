require "test_helper"

class CourseOutlineResearchBroadcastsTest < ActiveSupport::TestCase
  test "course row broadcast includes the current user for request-free rendering" do
    course = courses(:one)
    teacher = users(:admin)
    replace_calls = []

    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*args, **kwargs) {
      replace_calls << { args: args, kwargs: kwargs }
    }) do
      CourseOutlineResearchBroadcasts.broadcast_editor_state(course: course, current_user: teacher)
    end

    course_row_call = replace_calls.find do |call|
      call.dig(:kwargs, :partial) == "admin/courses/course"
    end

    assert_equal teacher, course_row_call.dig(:kwargs, :locals, :current_user)
    html = ApplicationController.render(
      partial: course_row_call.dig(:kwargs, :partial),
      locals: course_row_call.dig(:kwargs, :locals)
    )
    assert_includes html, course.title
  end
end
