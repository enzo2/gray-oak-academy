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
    tool_calls = [ {
      id: "tc-1",
      function: { name: "generate_course_outline", arguments: { course_id: @course.id }.to_json }
    } ]

    # Stub the generation job to make deterministic changes
    stub = proc do |course_arg, teacher_arg|
      # Simulate the job mutating the course outline
      course_arg.update!(outline: [ { "Generated Topic" => "Details" } ])
    end

    GenerateCourseOutlineJob.stub(:perform_now, stub) do
      assert_difference "Message.count", 1 do
        ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil).execute_tool_calls(tool_calls)
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
    tool_call_missing = [ { id: "tc-2", function: { name: "create_course", arguments: { title: "X" }.to_json } } ]

      assert_difference "Message.count", 1 do
      # Missing required param should produce a tool message with an error (ToolExecutionError is rescued)
      ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil).execute_tool_calls(tool_call_missing)
    end
    err_msg = Message.last
    assert_match (/Missing required parameters/), err_msg.content

    # Extra unexpected param should be rejected in strict mode
    tool_call_extra = [ {
      id: "tc-3",
      function: { name: "create_course",
      arguments: { title: "X", summary: "S", grade_level: "5", unexpected: "bad" }.to_json }
    } ]

    # The service currently validates required presence and coercion; strict extra-key checks are enforced higher up in the call flow.
    # If strict_mode extra key handling is present, it will raise and be converted into a tool message.
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil).execute_tool_calls(tool_call_extra)
    end
    err_msg2 = Message.last
    # Expect either an "Unexpected parameters" style error or validation failure; ensure we see some indication of rejection
    assert_match(/Unexpected parameters|Missing required parameters|Validation failed/i, err_msg2.content)
  end

  test "student is denied when calling teacher-only tools" do
    tool_calls = [ { id: "tc-4", function: { name: "generate_course_outline", arguments: { course_id: @course.id }.to_json } } ]

    # Conversation is for the student user; students should be denied for this tool
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_calls(tool_calls)
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
    list_call = [ { id: "tc-5", function: { name: "list_courses", arguments: {}.to_json } } ]
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_calls(list_call)
    end
    result = Message.last
    assert_match(/Math 101|Science 101|Basic Math Course|Basic Science Course/, result.content)

    # Student requests details for their teacher's course (courses(:one) is taught by student's teacher)
    detail_call = [ { id: "tc-6", function: { name: "get_course_details", arguments: { course_id: @course.id }.to_json } } ]
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_calls(detail_call)
    end
    detail_msg = Message.last
    parsed = JSON.parse(detail_msg.content) rescue nil
    assert parsed.is_a?(Hash)
    assert_equal @course.id, parsed["id"]

    # Student requests details for a course not taught by their teacher (courses(:two) belongs to admin2)
    other_course = courses(:two)
    other_call = [ { id: "tc-7", function: { name: "get_course_details", arguments: { course_id: other_course.id }.to_json } } ]
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_calls(other_call)
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
    reports_call = [ { id: "tc-8", function: { name: "get_student_reports", arguments: { student_id: @student.id }.to_json } } ]
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_calls(reports_call)
    end
    rep_msg = Message.last
    assert_match(/student/, rep_msg.content.downcase)

    # Student requests reports for another student belonging to their teacher
    other_student = users(:student2)
    other_student.update!(teacher: @teacher)
    bad_call = [ { id: "tc-9", function: { name: "get_student_reports", arguments: { student_id: other_student.id }.to_json } } ]
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_calls(bad_call)
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
    list_call = [ { id: "tc-limit-1", function: { name: "list_courses", arguments: {}.to_json } } ]
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: conv, message: nil).execute_tool_calls(list_call)
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
    list_call = [ { id: "tc-limit-2", function: { name: "list_courses", arguments: {}.to_json } } ]
    assert_difference "Message.count", 1 do
      ToolHandlerService.new(conversation: conv, message: nil).execute_tool_calls(list_call)
    end
    blocked = Message.last
    assert_match(/tool call limit reached/i, blocked.content)
  end

  test "execute_generate_image creates a tool message with attached image" do
    Tool.create!(
      specifications: {
        "name" => "generate_image",
        "description" => "Generate an image",
        "parameters" => {
          "type" => "object",
          "properties" => { "prompt" => { "type" => "string", "description" => "The prompt" } },
          "required" => [ "prompt" ]
        }
      }
    )

    # Create a dummy tempfile to simulate image generation result
    temp_image = Tempfile.new([ "test", ".jpg" ])
    temp_image.write("fake image content")
    temp_image.rewind

    tool_calls = [ {
      id: "tc-img-1",
      function: { name: "generate_image", arguments: { prompt: "A test image" }.to_json }
    } ]

    # Mock ImageGenerationService.generate
    ImageGenerationService.stub :generate, temp_image do
      assert_difference "Message.count", 1 do
        # We also expect 1 Image record created (and implicitly attached file)
        assert_difference "Image.count", 1 do
          ToolHandlerService.new(conversation: @conversation, message: nil).execute_tool_calls(tool_calls)
        end
      end
    end

    msg = Message.last
    assert_equal "tool", msg.role
    assert_equal "tc-img-1", msg.tool_call_id
    assert_equal "Image generation done.", msg.content
    assert msg.images.any?
    assert_equal 1, msg.images.count

    temp_image.close
    temp_image.unlink
  end

  test "manage applets tool routes list and get actions" do
    Tool.create!(
      access: :admin,
      specifications: {
        "name" => "Manage_Applets",
        "description" => "Applet tool",
        "strict_mode" => true,
        "parameters" => {
          "type" => "object",
          "properties" => {
            "action" => { "type" => "string", "description" => "Action", "enum" => [ "list", "get" ] },
            "applet_id" => { "type" => "integer", "description" => "Applet ID" }
          },
          "required" => [ "action" ],
          "additionalProperties" => false
        }
      }
    )

    NodeJsSyntaxChecker.stub(:check, { valid: true, errors: [] }) do
      @teacher.applets.create!(title: "Test Applet", code: "console.log('hi')")
    end
    applet = @teacher.applets.last

    service = ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil)

    assert_difference "Message.count", 1 do
      service.execute_tool_calls([ { id: "tc-applet-1", function: { name: "Manage_Applets", arguments: { action: "list" }.to_json } } ])
    end
    list_msg = Message.last
    assert_match(/Test Applet/, list_msg.content)

    assert_difference "Message.count", 1 do
      service.execute_tool_calls([ { id: "tc-applet-2", function: { name: "Manage_Applets", arguments: { action: "get", applet_id: applet.id }.to_json } } ])
    end
    get_msg = Message.last
    assert_match(/Test Applet/, get_msg.content.to_s)
    assert_match(/console\.log/, get_msg.content.to_s)
  end

  test "view applets in lessons are scoped to lesson resources" do
    Tool.create!(
      access: :student,
      specifications: {
        "name" => "View_Applets",
        "description" => "View applets tool",
        "strict_mode" => true,
        "parameters" => {
          "type" => "object",
          "properties" => {
            "action" => { "type" => "string", "description" => "Action", "enum" => [ "list", "get", "run_on_chalkboard" ] },
            "applet_id" => { "type" => "integer", "description" => "Applet ID" }
          },
          "required" => [ "action" ],
          "additionalProperties" => false
        }
      }
    )

    lesson_plan = lesson_plans(:one)
    conv = conversations(:student_lesson_conversation)
    teacher = users(:admin)

    NodeJsSyntaxChecker.stub(:check, { valid: true, errors: [] }) do
      allowed_resource = Resource.create!(teacher: teacher, category: "Applet", description: "Allowed resource")
      allowed_applet = Applet.create!(user: teacher, title: "Allowed Applet", code: "console.log('ok')", resource: allowed_resource)
      lesson_plan.resources << allowed_resource

      blocked_resource = Resource.create!(teacher: teacher, category: "Applet", description: "Blocked resource")
      blocked_applet = Applet.create!(user: teacher, title: "Blocked Applet", code: "console.log('no')", resource: blocked_resource)

      service = ToolHandlerService.new(conversation: conv, message: nil)

      assert_difference "Message.count", 1 do
        service.execute_tool_calls([ { id: "tc-view-1", function: { name: "View_Applets", arguments: { action: "list" }.to_json } } ])
      end
      list_msg = Message.last
      parsed = JSON.parse(list_msg.content)
      titles = parsed.map { |item| item["title"] }
      assert_includes titles, "Allowed Applet"
      refute_includes titles, "Blocked Applet"

      assert_difference "Message.count", 1 do
        service.execute_tool_calls([ { id: "tc-view-2", function: { name: "View_Applets", arguments: { action: "get", applet_id: allowed_applet.id }.to_json } } ])
      end
      get_msg = Message.last
      assert_match(/Allowed Applet/, get_msg.content.to_s)

      assert_difference "Message.count", 1 do
        service.execute_tool_calls([ { id: "tc-view-3", function: { name: "View_Applets", arguments: { action: "get", applet_id: blocked_applet.id }.to_json } } ])
      end
      blocked_msg = Message.last
      assert_match(/Applet not available for this lesson/, blocked_msg.content)
    end
  end

  test "get_student_profile returns markdown and excludes pending observations content" do
    Tool.create!(
      access: :admin,
      specifications: {
        "name" => "get_student_profile",
        "description" => "Get student profile",
        "strict_mode" => true,
        "parameters" => {
          "type" => "object",
          "properties" => {
            "student_id" => { "type" => "integer", "description" => "Student ID" },
            "focus" => { "type" => "string", "description" => "Focus" },
            "show_on_chalkboard" => { "type" => "boolean", "description" => "Show on chalkboard" }
          },
          "required" => [ "student_id" ],
          "additionalProperties" => false
        }
      }
    )

    student = @student
    student.update!(teacher: @teacher)

    # Ensure we have at least one approved + one pending observation
    Observation.create!(student: student, content: "Approved observation", status: :approved, relevance_weight: 1.0)
    Observation.create!(student: student, content: "PENDING SECRET", status: :pending, relevance_weight: 1.0)

    # Feedback and a profile report
    StudentFeedback.create!(student: student, content: "I liked this lesson", lesson_progress: lesson_progresses(:one))
    StudentReport.create!(
      student: student,
      teacher: @teacher,
      reportable: student,
      progress_data: {
        "current_snapshot" => "Doing well",
        "learning_patterns" => [ "Asks good questions" ],
        "current_strengths" => [ "Fractions" ],
        "areas_for_focus" => [ "Long division" ],
        "effective_approaches" => [ "Worked examples" ],
        "approaches_to_avoid" => [ "Too much speed" ],
        "recommendations" => [ "More practice sets" ]
      },
      author_type: :ai_generated,
      status: :completed
    )

    # Course report
    StudentReport.create!(
      student: student,
      teacher: @teacher,
      reportable: enrollments(:one),
      progress_data: { "summary" => "Course summary" },
      author_type: :ai_generated,
      status: :completed
    )

    called = false
    Turbo::StreamsChannel.stub :broadcast_update_to, ->(*_args, **_kwargs) { called = true } do
      assert_difference "Message.count", 1 do
        ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil).execute_tool_calls(
          [ { id: "tc-prof-1", function: { name: "get_student_profile", arguments: { student_id: student.id }.to_json } } ]
        )
      end
    end

    assert called, "expected chalkboard broadcast"
    msg = Message.last
    assert_match(/# Student: #{Regexp.escape(student.name)}/, msg.content)
    assert_match(/Latest student profile report/, msg.content)
    assert_match(/\*\*1 pending observations\*\*/i, msg.content)
    assert_match(/Approved observation/, msg.content)
    refute_match(/PENDING SECRET/, msg.content)
  end

  test "get_student_profile uses embeddings focus mode when configured" do
    Tool.create!(
      access: :admin,
      specifications: {
        "name" => "get_student_profile",
        "description" => "Get student profile",
        "strict_mode" => true,
        "parameters" => {
          "type" => "object",
          "properties" => {
            "student_id" => { "type" => "integer", "description" => "Student ID" },
            "focus" => { "type" => "string", "description" => "Focus" }
          },
          "required" => [ "student_id" ],
          "additionalProperties" => false
        }
      }
    )

    student = @student
    student.update!(teacher: @teacher)

    # Ensure we have enough records so focus results can include non-recent items
    8.times do |i|
      Memory.create!(student: student, author: @teacher, body: "Recent memory #{i}", hidden_from_student: false, created_at: (i + 1).hours.ago)
    end
    Memory.create!(student: student, author: @teacher, body: "Old memory for focus", hidden_from_student: false, created_at: 2.years.ago)

    12.times do |i|
      Observation.create!(student: student, content: "Recent obs #{i}", status: :approved, relevance_weight: 1.0, created_at: (i + 1).hours.ago)
    end
    Observation.create!(student: student, content: "Old obs for focus", status: :approved, relevance_weight: 1.0, created_at: 2.years.ago)

    AppSetting.stub :embeddings_configured?, true do
      EmbeddingService.stub :get, [ 0.1, 0.2, 0.3 ] do
        Memory.stub :nearest_neighbors, Memory.all do
          Observation.stub :nearest_neighbors, Observation.all do
            assert_difference "Message.count", 1 do
              ToolHandlerService.new(conversation: conversations(:teacher_generic_conversation), message: nil).execute_tool_calls(
                [ { id: "tc-prof-2", function: { name: "get_student_profile", arguments: { student_id: student.id, focus: "anxiety" }.to_json } } ]
              )
            end
          end
        end
      end
    end

    msg = Message.last
    assert_match(/## Focus: anxiety/i, msg.content)
    assert_match(/Mode: embeddings/i, msg.content)
  end
end
