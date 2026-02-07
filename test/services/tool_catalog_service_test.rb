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
end
