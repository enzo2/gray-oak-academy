require "test_helper"

class GenerateCourseOutlineJobTest < ActiveJob::TestCase
  test "job limits concurrency per course" do
    course = Struct.new(:id).new(42)
    user = Struct.new(:id).new(7)

    assert_equal 1, GenerateCourseOutlineJob.concurrency_limit
    assert_equal 10.minutes, GenerateCourseOutlineJob.concurrency_duration
    assert_equal "generate-course-outline-42", GenerateCourseOutlineJob.concurrency_key.call(course, user)
  end

  test "outline schema uses typed OpenAI base model and expected shape" do
    assert_equal "Course_Outline", GenerateCourseOutlineJob::OUTLINE_SCHEMA[:name]
    assert_equal true, GenerateCourseOutlineJob::OUTLINE_SCHEMA[:strict]

    assert_equal(
      {
        "type" => "object",
        "properties" => {
          "outline" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "topic" => { "type" => "string" },
                "description" => { "type" => "string" }
              },
              "required" => [ "topic", "description" ],
              "additionalProperties" => false
            }
          }
        },
        "required" => [ "outline" ],
        "additionalProperties" => false
      },
      GenerateCourseOutlineJob::OUTLINE_SCHEMA[:schema]
    )
  end

  test "raise_on_error propagates provider failures" do
    course = courses(:one)
    teacher = users(:admin)
    fake_service = Object.new

    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { fake_service }) do
      LlmServiceRouting.stub(:complete_structured_output, ->(**_kwargs) { raise StandardError, "provider unavailable" }) do
        Turbo::StreamsChannel.stub(:broadcast_replace_to, true) do
          Turbo::StreamsChannel.stub(:broadcast_update_to, true) do
            assert_raises(StandardError) do
              GenerateCourseOutlineJob.perform_now(course, teacher, raise_on_error: true)
            end
          end
        end
      end
    end
  end
end
