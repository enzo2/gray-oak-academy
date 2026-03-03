require "test_helper"

class ToolTest < ActiveSupport::TestCase
  test "valid_specifications rejects invalid schema and accepts valid schema" do
    invalid_tool = Tool.new(
      name: "invalid_tool",
      access: :student,
      specifications: { "foo" => "bar" }
    )
    assert_not invalid_tool.valid?
    assert_includes invalid_tool.errors[:specifications], "is not valid"

    valid_tool = Tool.new(
      name: "valid_tool",
      access: :student,
      specifications: {
        "name" => "valid_tool",
        "description" => "A valid tool",
        "parameters" => {
          "type" => "object",
          "properties" => {
            "arg1" => { "type" => "string", "description" => "A required argument" }
          },
          "required" => [ "arg1" ]
        }
      }
    )
    assert valid_tool.valid?, valid_tool.errors.full_messages.to_sentence
  end
end
