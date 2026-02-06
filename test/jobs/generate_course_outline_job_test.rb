require "test_helper"

class GenerateCourseOutlineJobTest < ActiveJob::TestCase
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
end
