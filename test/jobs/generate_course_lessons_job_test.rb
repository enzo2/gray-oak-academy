require "test_helper"

class GenerateCourseLessonsJobTest < ActiveJob::TestCase
  test "job limits concurrency per course" do
    course = Struct.new(:id).new(24)
    user = Struct.new(:id).new(9)

    assert_equal 1, GenerateCourseLessonsJob.concurrency_limit
    assert_equal 10.minutes, GenerateCourseLessonsJob.concurrency_duration
    assert_equal "generate-course-lessons-24", GenerateCourseLessonsJob.concurrency_key.call(course, user)
  end

  test "broadcast_success replaces the lessons action button" do
    job = GenerateCourseLessonsJob.new
    teacher = users(:admin)
    course = courses(:one)
    calls = []
    renderer = Class.new do
      def render(**)
        "<div>rendered lessons</div>"
      end
    end.new

    ApplicationController.stub :renderer_with_signed_in_user, renderer do
      Turbo::StreamsChannel.stub :broadcast_update_to, ->(*args, **kwargs) { calls << [ :update, args, kwargs ] } do
        Turbo::StreamsChannel.stub :broadcast_replace_to, ->(*args, **kwargs) { calls << [ :replace, args, kwargs ] } do
          job.send(:broadcast_success, teacher, course)
        end
      end
    end

    assert_includes calls, [
      :update,
      [ "teacher_#{teacher.id}-dashboard" ],
      { target: "lessons-table-body", html: "<div>rendered lessons</div>" }
    ]
    assert_includes calls, [
      :replace,
      [ "teacher_#{teacher.id}-dashboard" ],
      {
        target: "generate-lessons-button",
        partial: "admin/lessons/generate_lessons_button",
        locals: { course: course.reload }
      }
    ]
  end

  test "broadcast_error replaces the lessons action button" do
    job = GenerateCourseLessonsJob.new
    teacher = users(:admin)
    course = courses(:one)
    calls = []

    Turbo::StreamsChannel.stub :broadcast_update_to, ->(*args, **kwargs) { calls << [ :update, args, kwargs ] } do
      Turbo::StreamsChannel.stub :broadcast_replace_to, ->(*args, **kwargs) { calls << [ :replace, args, kwargs ] } do
        job.send(:broadcast_error, teacher, course, "Failed")
      end
    end

    assert_includes calls, [
      :update,
      [ "teacher_#{teacher.id}-dashboard" ],
      { target: "flash_bar", partial: "shared/flash", locals: { flash: { error: "Failed" } } }
    ]
    assert_includes calls, [
      :replace,
      [ "teacher_#{teacher.id}-dashboard" ],
      {
        target: "generate-lessons-button",
        partial: "admin/lessons/generate_lessons_button",
        locals: { course: course }
      }
    ]
  end

  test "raise_on_error propagates provider failures" do
    course = courses(:one)
    teacher = users(:admin)
    fake_service = Object.new

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_service }) do
      LlmServiceRouting.stub(:complete_structured_output, ->(**_kwargs) { raise StandardError, "provider unavailable" }) do
        Turbo::StreamsChannel.stub(:broadcast_update_to, true) do
          Turbo::StreamsChannel.stub(:broadcast_replace_to, true) do
            assert_raises(StandardError) do
              GenerateCourseLessonsJob.perform_now(course, teacher, raise_on_error: true)
            end
          end
        end
      end
    end
  end
end
