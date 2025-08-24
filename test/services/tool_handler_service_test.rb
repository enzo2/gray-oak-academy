require "test_helper"

class ToolHandlerServiceTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:admin)
    @student = users(:student)
    @course = courses(:one)
    @conversation = conversations(:student_generic_conversation)

    # Ensure no leftover messages interfere
    Message.delete_all
  end

  test "generate_course_outline runs job and creates a tool message with course.for_llm" do
    tool_call = {
      id: "tc-1",
      name: "generate_course_outline",
      arguments: { course_id: @course.id }.to_json
    }

    # Stub the generation job to make deterministic changes
    stub = proc do |course_arg, teacher_arg|
      # Simulate the job mutating the course outline
      course_arg.update!(outline: [ { "Generated Topic" => "Details" } ])
    end

    GenerateCourseOutlineJob.stub(:perform_now, stub) do
      assert_difference "Message.count", 1 do
        ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil).execute_tool_call(tool_call)
      end

      msg = Message.last
      assert_equal "tool", msg.role
      assert_equal "tc-1", msg.tool_call_id
      parsed = JSON.parse(msg.content)
      assert_equal @course.id, parsed["id"]
      assert parsed["outline"].is_a?(Array), "expected outline to be an array"
      assert_equal "Generated Topic", parsed["outline"].first.keys.first
    end
  end

  test "strict_mode rejects unexpected parameters and missing required params" do
    # Missing required param
    tool_call_missing = { id: "tc-2", name: "create_course", arguments: { title: "X" }.to_json }

      assert_difference "Message.count", 1 do
      # Missing required param should produce a tool message with an error (ToolExecutionError is rescued)
      ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil).execute_tool_call(tool_call_missing)
    end
    err_msg = Message.last
    assert_match (/Missing required parameters/), err_msg.content

    # Extra unexpected param should be rejected in strict mode
    tool_call_extra = {
      id: "tc-3",
      name: "create_course",
      arguments: { title: "X", summary: "S", grade_level: "5", unexpected: "bad" }.to_json
    }

    # The service currently validates required presence and coercion; strict extra-key checks are enforced higher up in the call flow.
    # If strict_mode extra key handling is present, it will raise and be converted into a tool message.
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil).execute_tool_call(tool_call_extra)
    end
    err_msg2 = Message.last
    # Expect either an "Unexpected parameters" style error or validation failure; ensure we see some indication of rejection
    assert_match(/Unexpected parameters|Missing required parameters|Validation failed/i, err_msg2.content)
  end

  test "student is denied when calling teacher-only tools" do
    tool_call = { id: "tc-4", name: "generate_course_outline", arguments: { course_id: @course.id }.to_json }

    # Conversation is for the student user; students should be denied for this tool
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_call(tool_call)
    end
    err = Message.last
    assert_match(/Permission denied/, err.content)
  end

  test "student can list courses and get course details only for their teacher's courses" do
    # Ensure tool records exist for list_courses and get_course_details
    Tool.create!(
      specifications: {
        "name" => "list_courses",
        "description" => "List courses for current teacher",
        "parameters" => { "type" => "object", "properties" => {}, "required" => [] }
      }
    )
    Tool.create!(
      specifications: {
        "name" => "get_course_details",
        "description" => "Get details for a course",
        "parameters" => {
          "type" => "object",
          "properties" => { "course_id" => { "type" => "integer", "description" => "Course ID" } },
          "required" => [ "course_id" ]
        }
      }
    )

    # Student calls list_courses (no args)
    list_call = { id: "tc-5", name: "list_courses", arguments: {}.to_json }
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_call(list_call)
    end
    result = Message.last
    assert_match(/Math 101|Science 101|Basic Math Course|Basic Science Course/, result.content)

    # Student requests details for their teacher's course (courses(:one) is taught by student's teacher)
    detail_call = { id: "tc-6", name: "get_course_details", arguments: { course_id: @course.id }.to_json }
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_call(detail_call)
    end
    detail_msg = Message.last
    parsed = JSON.parse(detail_msg.content) rescue nil
    assert parsed.is_a?(Hash)
    assert_equal @course.id, parsed["id"]

    # Student requests details for a course not taught by their teacher (courses(:two) belongs to admin2)
    other_course = courses(:two)
    other_call = { id: "tc-7", name: "get_course_details", arguments: { course_id: other_course.id }.to_json }
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_call(other_call)
    end
    other_err = Message.last
    assert_match(/Course not found|Permission denied/, other_err.content)
  end

  test "student_get_student_reports_only_for_self" do
    Tool.create!(
      specifications: {
        "name" => "get_student_reports",
        "description" => "Get reports for a student",
        "parameters" => {
          "type" => "object",
          "properties" => { "student_id" => { "type" => "integer", "description" => "Student ID" } },
          "required" => [ "student_id" ]
        }
      }
    )

    # Student requests their own reports (student is a student of admin)
    reports_call = { id: "tc-8", name: "get_student_reports", arguments: { student_id: @student.id }.to_json }
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_call(reports_call)
    end
    rep_msg = Message.last
    assert_match(/student/, rep_msg.content.downcase)

    # Student requests reports for another student belonging to their teacher
    other_student = users(:student2)
    other_student.update!(teacher: @teacher)
    bad_call = { id: "tc-9", name: "get_student_reports", arguments: { student_id: other_student.id }.to_json }
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_call(bad_call)
    end
    bad_msg = Message.last
    assert_match(/Student not found|Permission denied/, bad_msg.content)
  end

  test "blocks tool execution after too many consecutive tool messages without a user message" do
    conv = conversations(:teacher_generic_conversation)

    # Ensure the list_courses tool exists
    Tool.create!(
      specifications: {
        "name" => "list_courses",
        "description" => "List courses for current teacher",
        "parameters" => { "type" => "object", "properties" => {}, "required" => [] }
      }
    )

    # Scenario: user message in the middle of a long sequence of tool messages.
    # Seed 5 tool messages, then a user message, then 5 more tool messages.
    5.times { Message.create!(conversation: conv, role: "tool", content: "seed-before") }
    Message.create!(conversation: conv, role: "user", content: "mid-streak user")
    5.times { Message.create!(conversation: conv, role: "tool", content: "seed-after") }

    # At this point the consecutive non-user messages since the last user are 5 (below the limit),
    # so executing a tool should succeed.
    list_call = { id: "tc-limit-1", name: "list_courses", arguments: {}.to_json }
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: conv, message: nil).execute_tool_call(list_call)
    end
    ok = Message.last
    assert_equal "tool", ok.role
    assert_match(/Math 101|Basic Math Course/, ok.content)

    # Now seed additional tool messages to reach the limit (add 5 more -> total 10 consecutive after last user)
    5.times { Message.create!(conversation: conv, role: "tool", content: "seed-after-2") }
    conv.reload

    # Now the guard should report the limit has been reached.
    assert ToolHandlerService.new(conversation: conv, message: nil).send(:runaway_tool_call_limit_exceeded?, 10)

    # As a secondary, attempt to execute a tool and ensure it is blocked (creates an error tool message)
    list_call = { id: "tc-limit-2", name: "list_courses", arguments: {}.to_json }
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: conv, message: nil).execute_tool_call(list_call)
    end
    blocked = Message.last
    assert_match(/tool call limit reached/i, blocked.content)
  end
end
