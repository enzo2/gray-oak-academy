require "test_helper"

class ToolExecutionServiceTest < ActiveSupport::TestCase
  test "unexpected tool errors are returned as tool messages" do
    conversation = conversations(:teacher_generic_conversation)
    tool = Tool.find_or_initialize_by(name: "list_courses")
    tool.access = :admin
    tool.specifications = {
      "name" => "list_courses",
      "description" => "List available courses",
      "parameters" => {
        "type" => "object",
        "properties" => {},
        "required" => []
      }
    }
    tool.save!

    service = ToolExecutionService.new(conversation: conversation, message: nil)

    service.stub(:execute_list_courses, -> { raise "boom" }) do
      assert_difference "Message.count", 1 do
        service.execute_tool_call(
          id: "tc-unexpected-1",
          name: "list_courses",
          arguments: {}.to_json
        )
      end
    end

    tool_message = Message.order(:created_at).last
    assert_equal "tool", tool_message.role
    assert_equal "tc-unexpected-1", tool_message.tool_call_id
    assert_includes tool_message.content, "Tool execution resulted in error: boom"
  end

  test "tool name lookup treats wildcards literally" do
    conversation = conversations(:teacher_generic_conversation)
    tool = Tool.find_or_initialize_by(name: "list_courses")
    tool.access = :admin
    tool.specifications = {
      "name" => "list_courses",
      "description" => "List available courses",
      "parameters" => {
        "type" => "object",
        "properties" => {},
        "required" => []
      }
    }
    tool.save!

    service = ToolExecutionService.new(conversation: conversation, message: nil)

    assert_difference "Message.count", 1 do
      service.execute_tool_call(
        id: "tc-wildcard-1",
        name: "list%courses",
        arguments: {}.to_json
      )
    end

    tool_message = Message.order(:created_at).last
    assert_equal "tool", tool_message.role
    assert_includes tool_message.content, "Tool 'list%courses' not found"
  end

  test "invalid JSON repair errors return explicit repair failure message" do
    conversation = conversations(:teacher_generic_conversation)
    tool = Tool.find_or_initialize_by(name: "list_courses")
    tool.access = :admin
    tool.specifications = {
      "name" => "list_courses",
      "description" => "List available courses",
      "parameters" => {
        "type" => "object",
        "properties" => {},
        "required" => []
      }
    }
    tool.save!

    service = ToolExecutionService.new(conversation: conversation, message: nil)

    JSON.stub(:repair, ->(_json) { raise JSON::JSONRepairError.new("bad json") }) do
      assert_difference "Message.count", 1 do
        service.execute_tool_call(
          id: "tc-json-repair-1",
          name: "list_courses",
          arguments: "{bad-json"
        )
      end
    end

    tool_message = Message.order(:created_at).last
    assert_equal "tool", tool_message.role
    assert_includes tool_message.content, "Invalid JSON in tool arguments, unable to repair."
  end
end
