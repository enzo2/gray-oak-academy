require "test_helper"

class ToolCatalogServiceTest < ActiveSupport::TestCase
  test "filters view applets for teachers in non-lesson conversations" do
    teacher = users(:admin)
    conversation = conversations(:teacher_generic_conversation)

    view_tool = Tool.find_or_create_by!(specifications: {
      "name" => "View_Applets",
      "description" => "View applets",
      "parameters" => { "type" => "object", "properties" => {}, "required" => [] }
    }) do |tool|
      tool.access = :admin
    end
    view_tool.update!(access: :admin)

    manage_tool = Tool.find_or_create_by!(specifications: {
      "name" => "Manage_Applets",
      "description" => "Manage applets",
      "parameters" => { "type" => "object", "properties" => {}, "required" => [] }
    }) do |tool|
      tool.access = :admin
    end
    manage_tool.update!(access: :admin)

    tools = ToolCatalogService.new(
      user: teacher,
      conversation: conversation,
      base_uri: "https://api.openai.com/v1/"
    ).for_chat_completions

    names = tools.map { |tool| tool.dig("function", "name") }
    assert_includes names, "Manage_Applets"
    refute_includes names, "View_Applets"
  end

  test "limits tools to student access in lesson conversations" do
    teacher = users(:admin)
    lesson_conversation = Conversation.create!(
      user: teacher,
      title: "Teacher lesson preview",
      lesson_progress: lesson_progresses(:one)
    )

    student_tool = Tool.find_or_create_by!(specifications: {
      "name" => "Student_Only_Tool",
      "description" => "Student tool",
      "parameters" => { "type" => "object", "properties" => {}, "required" => [] }
    }) do |tool|
      tool.access = :student
    end
    student_tool.update!(access: :student)

    admin_tool = Tool.find_or_create_by!(specifications: {
      "name" => "Admin_Only_Tool",
      "description" => "Admin tool",
      "parameters" => { "type" => "object", "properties" => {}, "required" => [] }
    }) do |tool|
      tool.access = :admin
    end
    admin_tool.update!(access: :admin)

    response_tools = ToolCatalogService.new(
      user: teacher,
      conversation: lesson_conversation,
      base_uri: "https://api.openai.com/v1/"
    ).for_responses

    names = response_tools.map { |tool| tool["name"] }
    assert_includes names, "Student_Only_Tool"
    refute_includes names, "Admin_Only_Tool"
  end

  test "responses tools default to strict false when strict_mode is unset" do
    teacher = users(:admin)
    conversation = conversations(:teacher_generic_conversation)

    tool = Tool.find_or_initialize_by(name: "Strict_Default_False")
    tool.access = :admin
    tool.specifications = {
      "name" => "Strict_Default_False",
      "description" => "Tool with no strict_mode specified",
      "parameters" => {
        "type" => "object",
        "properties" => {},
        "required" => []
      }
    }
    tool.save!

    response_tool = ToolCatalogService.new(
      user: teacher,
      conversation: conversation,
      base_uri: "https://api.openai.com/v1/"
    ).for_responses.find { |entry| entry["name"] == "Strict_Default_False" }

    assert_not_nil response_tool
    assert_equal false, response_tool["strict"]
  end

  test "responses tools preserve strict true when strict_mode is set" do
    teacher = users(:admin)
    conversation = conversations(:teacher_generic_conversation)

    tool = Tool.find_or_initialize_by(name: "Strict_Enabled_Tool")
    tool.access = :admin
    tool.specifications = {
      "name" => "Strict_Enabled_Tool",
      "description" => "Tool with strict mode enabled",
      "strict_mode" => true,
      "parameters" => {
        "type" => "object",
        "properties" => {},
        "required" => [],
        "additionalProperties" => false
      }
    }
    tool.save!

    response_tool = ToolCatalogService.new(
      user: teacher,
      conversation: conversation,
      base_uri: "https://api.openai.com/v1/"
    ).for_responses.find { |entry| entry["name"] == "Strict_Enabled_Tool" }

    assert_not_nil response_tool
    assert_equal true, response_tool["strict"]
  end

  test "web tool is hidden from chat completions when Exa is disabled" do
    teacher = users(:admin)
    conversation = conversations(:teacher_generic_conversation)

    tool = Tool.find_or_initialize_by(name: "Web")
    tool.access = :admin
    tool.specifications = {
      "name" => "Web",
      "description" => "Web tool",
      "parameters" => {
        "type" => "object",
        "properties" => { "action" => { "type" => "string", "description" => "Action" } },
        "required" => [ "action" ]
      }
    }
    tool.save!

    AppSetting.stub(:exa_enabled?, false) do
      tools = ToolCatalogService.new(
        user: teacher,
        conversation: conversation,
        base_uri: "https://api.openai.com/v1/"
      ).for_chat_completions
      names = tools.map { |entry| entry.dig("function", "name") }
      refute_includes names, "Web"
    end
  end

  test "web tool is included in responses when Exa is enabled" do
    teacher = users(:admin)
    conversation = conversations(:teacher_generic_conversation)

    tool = Tool.find_or_initialize_by(name: "Web")
    tool.access = :admin
    tool.specifications = {
      "name" => "Web",
      "description" => "Web tool",
      "parameters" => {
        "type" => "object",
        "properties" => { "action" => { "type" => "string", "description" => "Action" } },
        "required" => [ "action" ]
      }
    }
    tool.save!

    AppSetting.stub(:exa_enabled?, true) do
      tools = ToolCatalogService.new(
        user: teacher,
        conversation: conversation,
        base_uri: "https://api.openai.com/v1/"
      ).for_responses
      names = tools.map { |entry| entry["name"] }
      assert_includes names, "Web"
    end
  end
end
