require "test_helper"

class ToolExecutionServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "execute_show_on_chalkboard with url renders iframe tab for embeddable URL" do
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    service.instance_variable_set(:@args, { "url" => "https://example.com/embeddable" })
    service.instance_variable_set(:@tool_call_id, "tc-embed-1")

    embed_result = {
      status: "embeddable",
      reason: "No blocking iframe headers detected.",
      final_url: "https://example.com/embeddable",
      x_frame_options: nil,
      csp_frame_ancestors: nil
    }

    broadcast_args = nil

    UrlEmbeddabilityService.stub(:check, embed_result) do
      service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
        assert_difference "Message.count", 1 do
          service.send(:execute_show_on_chalkboard)
        end
      end
    end

    assert_equal "shared/chalkboard_iframe", broadcast_args[:partial]
    assert_equal({ url: "https://example.com/embeddable" }, broadcast_args[:locals])
    assert_includes Message.order(:created_at).last.content, "[Open link](https://example.com/embeddable)"
  end

  test "execute_show_on_chalkboard with url renders fallback tab for x-frame blocked URL" do
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    service.instance_variable_set(:@args, { "url" => "https://example.com/blocked" })
    service.instance_variable_set(:@tool_call_id, "tc-blocked-1")

    embed_result = {
      status: "blocked_xfo",
      reason: "Site blocks embedding via X-Frame-Options.",
      final_url: "https://example.com/blocked",
      x_frame_options: "SAMEORIGIN",
      csp_frame_ancestors: nil
    }

    broadcast_args = nil

    UrlEmbeddabilityService.stub(:check, embed_result) do
      service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
        assert_difference "Message.count", 1 do
          service.send(:execute_show_on_chalkboard)
        end
      end
    end

    assert_equal "shared/chalkboard_link_fallback", broadcast_args[:partial]
    assert_equal "Site blocks embedding via X-Frame-Options.", broadcast_args.dig(:locals, :reason)
    assert_includes Message.order(:created_at).last.content, "blocks iframe embedding"
  end

  test "execute_show_on_chalkboard with url keeps iframe attempt and adds markdown link when embeddability is unknown" do
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    service.instance_variable_set(:@args, { "url" => "https://example.com/unknown" })
    service.instance_variable_set(:@tool_call_id, "tc-unknown-1")

    embed_result = {
      status: "unknown",
      reason: "Could not verify embeddability.",
      final_url: "https://example.com/unknown",
      x_frame_options: nil,
      csp_frame_ancestors: nil
    }

    broadcast_args = nil

    UrlEmbeddabilityService.stub(:check, embed_result) do
      service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
        assert_difference "Message.count", 1 do
          service.send(:execute_show_on_chalkboard)
        end
      end
    end

    assert_equal "shared/chalkboard_iframe", broadcast_args[:partial]
    assert_includes Message.order(:created_at).last.content, "Embeddability check was inconclusive"
    assert_includes Message.order(:created_at).last.content, "[Open link](https://example.com/unknown)"
  end

  test "execute_show_on_chalkboard with resource_id renders file payload" do
    conversation = conversations(:teacher_generic_conversation)
    teacher = users(:admin)
    resource = Resource.create!(teacher: teacher, category: "File", description: "Worksheet")
    resource.file.attach(io: StringIO.new("%PDF-1.4 sample"), filename: "worksheet.pdf", content_type: "application/pdf")
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    service.instance_variable_set(:@args, { "resource_id" => resource.id.to_s })
    service.instance_variable_set(:@tool_call_id, "tc-resource-file-1")

    broadcast_args = nil
    service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
      assert_difference "Message.count", 1 do
        service.send(:execute_show_on_chalkboard)
      end
    end

    assert_equal "shared/chalkboard_file", broadcast_args[:partial]
    assert_equal "application/pdf", broadcast_args.dig(:locals, :file_type)
    assert_equal "worksheet.pdf", broadcast_args.dig(:locals, :filename)
    assert_includes Message.order(:created_at).last.content, "Chalkboard updated with file: worksheet.pdf"
  end

  test "execute_show_on_chalkboard with resource_id routes uri resources through url flow" do
    conversation = conversations(:teacher_generic_conversation)
    teacher = users(:admin)
    resource = Resource.create!(
      teacher: teacher,
      category: "Website",
      description: "Fractions site",
      uri: "https://example.com/resource-uri"
    )
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    service.instance_variable_set(:@args, { "resource_id" => resource.id.to_s })
    service.instance_variable_set(:@tool_call_id, "tc-resource-uri-1")

    embed_result = {
      status: "embeddable",
      reason: "No blocking iframe headers detected.",
      final_url: resource.uri,
      x_frame_options: nil,
      csp_frame_ancestors: nil
    }
    broadcast_args = nil

    UrlEmbeddabilityService.stub(:check, embed_result) do
      service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
        assert_difference "Message.count", 1 do
          service.send(:execute_show_on_chalkboard)
        end
      end
    end

    assert_equal "shared/chalkboard_iframe", broadcast_args[:partial]
    assert_equal "Resource Link", broadcast_args[:tab_title]
    assert_equal({ url: resource.uri }, broadcast_args[:locals])
    assert_includes Message.order(:created_at).last.content, "[Open link](https://example.com/resource-uri)"
  end

  test "execute_show_on_chalkboard with resource_id renders text payload" do
    conversation = conversations(:teacher_generic_conversation)
    teacher = users(:admin)
    resource = Resource.create!(
      teacher: teacher,
      category: "Text",
      description: "Warmup notes",
      content: "# Warmup\nDiscuss one key idea."
    )
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    service.instance_variable_set(:@args, { "resource_id" => resource.id.to_s })
    service.instance_variable_set(:@tool_call_id, "tc-resource-text-1")

    broadcast_args = nil
    service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
      assert_difference "Message.count", 1 do
        service.send(:execute_show_on_chalkboard)
      end
    end

    assert_equal "shared/chalkboard_text_resource", broadcast_args[:partial]
    assert_equal "Warmup notes", broadcast_args[:tab_title]
    assert_equal "Text", broadcast_args.dig(:locals, :resource_name)
    assert_equal "Warmup notes", broadcast_args.dig(:locals, :resource_description)
    assert_includes broadcast_args.dig(:locals, :text_content), "# Warmup"
    assert_includes Message.order(:created_at).last.content, "Chalkboard updated with text resource: Warmup notes"
  end

  test "execute_show_on_chalkboard with resource_id registers applet payload on chalkboard" do
    conversation = conversations(:teacher_generic_conversation)
    teacher = users(:admin)
    resource = nil

    NodeJsSyntaxChecker.stub(:check, { valid: true, errors: [] }) do
      resource = Resource.new(teacher: teacher, category: "Applet", description: "Graph applet")
      resource.build_applet(user: teacher, title: "Graph Explorer", code: "const value = 1;")
      resource.save!
    end

    service = ToolExecutionService.new(conversation: conversation, message: nil)
    service.instance_variable_set(:@args, { "resource_id" => resource.id.to_s })
    service.instance_variable_set(:@tool_call_id, "tc-resource-applet-1")

    payload = nil
    service.stub(:broadcast_chalkboard_event, ->(kwargs) { payload = kwargs }) do
      assert_difference "Message.count", 1 do
        service.send(:execute_show_on_chalkboard)
      end
    end

    assert_equal "register_applet", payload[:event_type]
    assert_equal "resource", payload[:source]
    assert_equal "resource_#{resource.id}", payload[:key]
    assert_equal resource.applet.id, payload[:applet_id]
    assert_includes Message.order(:created_at).last.content, "Graph Explorer"
  end

  test "execute_tool_call enforces lesson-linked resource scope for show_on_chalkboard" do
    create_show_on_chalkboard_tool!
    conversation = conversations(:student_lesson_conversation)
    resource = Resource.create!(
      teacher: users(:admin),
      category: "Text",
      description: "Not linked",
      content: "Unlinked lesson content"
    )
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    assert_difference "Message.count", 1 do
      service.execute_tool_call(
        id: "tc-scope-1",
        name: "Show_On_Chalkboard",
        arguments: { resource_id: resource.id.to_s }.to_json
      )
    end

    assert_includes Message.order(:created_at).last.content, "Resource not available for this lesson"
  end

  test "execute_tool_call rejects show_on_chalkboard arguments when both url and resource_id are provided" do
    create_show_on_chalkboard_tool!
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    assert_difference "Message.count", 1 do
      service.execute_tool_call(
        id: "tc-show-args-both",
        name: "Show_On_Chalkboard",
        arguments: { url: "https://example.com", resource_id: "1" }.to_json
      )
    end

    assert_includes Message.order(:created_at).last.content, "Provide exactly one argument"
  end

  test "execute_tool_call rejects show_on_chalkboard arguments when neither url nor resource_id is provided" do
    create_show_on_chalkboard_tool!
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    assert_difference "Message.count", 1 do
      service.execute_tool_call(
        id: "tc-show-args-neither",
        name: "Show_On_Chalkboard",
        arguments: {}.to_json
      )
    end

    assert_includes Message.order(:created_at).last.content, "Provide exactly one argument"
  end

  test "web tool action search uses Exa search with bounded num_results" do
    create_web_tool!
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    captured = {}
    fake_exa = Object.new
    fake_exa.define_singleton_method(:search) do |**kwargs|
      captured[:search] = kwargs
      { "results" => [ { "title" => "Fractions guide", "url" => "https://example.com/fractions" } ] }
    end

    ExaApiService.stub(:new, ->(**_kwargs) { fake_exa }) do
      assert_difference "Message.count", 1 do
        service.execute_tool_call(
          id: "tc-web-search",
          name: "Web",
          arguments: { action: "search", query: "grade 5 fractions", num_results: 500 }.to_json
        )
      end
    end

    assert_equal "grade 5 fractions", captured.dig(:search, :query)
    assert_equal 20, captured.dig(:search, :numResults)
    assert_equal false, captured.dig(:search, :contents, :text)
    assert_equal 2000, captured.dig(:search, :contents, :highlights, :maxCharacters)
    assert_includes Message.order(:created_at).last.content.to_s, "Fractions guide"
  end

  test "web tool action answer uses Exa answer" do
    create_web_tool!
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    captured = {}
    fake_exa = Object.new
    fake_exa.define_singleton_method(:answer) do |**kwargs|
      captured[:answer] = kwargs
      { "answer" => "A fraction represents part of a whole." }
    end

    ExaApiService.stub(:new, ->(**_kwargs) { fake_exa }) do
      assert_difference "Message.count", 1 do
        service.execute_tool_call(
          id: "tc-web-answer",
          name: "Web",
          arguments: { action: "answer", query: "What is a fraction?" }.to_json
        )
      end
    end

    assert_equal "What is a fraction?", captured.dig(:answer, :query)
    assert_includes Message.order(:created_at).last.content.to_s, "part of a whole"
  end

  test "web tool action content validates required urls" do
    create_web_tool!
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    assert_difference "Message.count", 1 do
      service.execute_tool_call(
        id: "tc-web-content-missing-urls",
        name: "Web",
        arguments: { action: "content", query: "methodology" }.to_json
      )
    end

    assert_includes Message.order(:created_at).last.content.to_s, "urls is required for action 'content'"
  end

  test "web tool action content uses fixed text max characters" do
    create_web_tool!
    conversation = conversations(:teacher_generic_conversation)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    captured = {}
    fake_exa = Object.new
    fake_exa.define_singleton_method(:get_contents) do |**kwargs|
      captured[:contents] = kwargs
      { "results" => [ { "url" => "https://example.com/paper", "text" => "excerpt" } ] }
    end

    ExaApiService.stub(:new, ->(**_kwargs) { fake_exa }) do
      assert_difference "Message.count", 1 do
        service.execute_tool_call(
          id: "tc-web-content",
          name: "Web",
          arguments: {
            action: "content",
            urls: [ "https://example.com/paper" ],
            query: "methodology"
          }.to_json
        )
      end
    end

    assert_equal [ "https://example.com/paper" ], captured.dig(:contents, :urls)
    assert_equal 4000, captured.dig(:contents, :text, :maxCharacters)
    assert_equal "methodology", captured.dig(:contents, :highlights, :query)
    assert_equal 4000, captured.dig(:contents, :highlights, :maxCharacters)
    assert_includes Message.order(:created_at).last.content.to_s, "https://example.com/paper"
  end

  test "generate_lesson_plan runs synchronous content generation when action is generate_content" do
    Rails.cache.clear
    create_generate_lesson_plan_tool!
    conversation = conversations(:teacher_generic_conversation)
    lesson = lessons(:one)
    lesson.lesson_plan.update!(generation_stage: "idle")
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    perform_called = false
    GenerateLessonPlanContentJob.stub(:perform_now, ->(*_args) { perform_called = true }) do
      assert_no_enqueued_jobs do
        assert_difference "Message.count", 1 do
          service.execute_tool_call(
            id: "tc-generate-default",
            name: "Generate_Lesson_Plan",
            arguments: { lesson_id: lesson.id, action: "generate_content" }.to_json
          )
        end
      end
    end

    assert_equal true, perform_called
    refute_includes Message.order(:created_at).last.content.to_s, "Tool execution resulted in error"
  end

  test "generate_lesson_plan requires explicit action" do
    Rails.cache.clear
    create_generate_lesson_plan_tool!
    conversation = conversations(:teacher_generic_conversation)
    lesson = lessons(:one)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    assert_difference "Message.count", 1 do
      service.execute_tool_call(
        id: "tc-generate-missing-action",
        name: "Generate_Lesson_Plan",
        arguments: { lesson_id: lesson.id }.to_json
      )
    end

    assert_includes Message.order(:created_at).last.content.to_s, "Missing required parameters: action"
  end

  test "generate_lesson_plan action propose_resources_async enqueues propose resources job" do
    Rails.cache.clear
    create_generate_lesson_plan_tool!
    conversation = conversations(:teacher_generic_conversation)
    lesson = lessons(:one)
    lesson.lesson_plan.update!(generation_stage: "completed")
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    AppSetting.stub(:openai_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 1, only: ProposeResourcesJob do
          assert_difference "Message.count", 1 do
            service.execute_tool_call(
              id: "tc-generate-propose-async",
              name: "Generate_Lesson_Plan",
              arguments: { lesson_id: lesson.id, action: "propose_resources_async" }.to_json
            )
          end
        end
      end
    end

    body = Message.order(:created_at).last.content.to_s
    assert_includes body, "\"status\": \"queued\""
    assert_includes body, "\"action\": \"propose_resources_async\""
  end

  test "generate_lesson_plan action generate_content_and_propose_resources_async enqueues pipeline job" do
    Rails.cache.clear
    create_generate_lesson_plan_tool!
    conversation = conversations(:teacher_generic_conversation)
    lesson = lessons(:one)
    lesson.lesson_plan.update!(generation_stage: "idle")
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    AppSetting.stub(:openai_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
          assert_difference "Message.count", 1 do
            service.execute_tool_call(
              id: "tc-generate-content-and-propose-async",
              name: "Generate_Lesson_Plan",
              arguments: { lesson_id: lesson.id, action: "generate_content_and_propose_resources_async" }.to_json
            )
          end
        end
      end
    end

    body = Message.order(:created_at).last.content.to_s
    assert_includes body, "\"status\": \"queued\""
    assert_includes body, "\"action\": \"generate_content_and_propose_resources_async\""
  end

  test "generate_lesson_plan async actions return meaningful precondition errors" do
    Rails.cache.clear
    create_generate_lesson_plan_tool!
    conversation = conversations(:teacher_generic_conversation)
    lesson = lessons(:one)
    lesson.lesson_plan.update!(generation_stage: "idle")
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    AppSetting.stub(:openai_agent_enabled?, false) do
      AppSetting.stub(:exa_enabled?, false) do
        assert_difference "Message.count", 1 do
          service.execute_tool_call(
            id: "tc-generate-propose-disabled",
            name: "Generate_Lesson_Plan",
            arguments: { lesson_id: lesson.id, action: "propose_resources_async" }.to_json
          )
        end
      end
    end
    assert_includes Message.order(:created_at).last.content.to_s, "Configure OpenAI Agent Runs and Exa API before proposing resources."

    AppSetting.stub(:openai_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_difference "Message.count", 1 do
          service.execute_tool_call(
            id: "tc-generate-propose-prereq",
            name: "Generate_Lesson_Plan",
            arguments: { lesson_id: lesson.id, action: "propose_resources_async" }.to_json
          )
        end
      end
    end
    assert_includes Message.order(:created_at).last.content.to_s, "Generate the lesson plan once before proposing resources."
  end

  test "generate_course_outline action research_outline queues outline research asynchronously" do
    create_generate_course_outline_tool!
    conversation = conversations(:teacher_generic_conversation)
    course = courses(:one)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    captured_kwargs = {}
    fake_async_service = Object.new
    fake_async_service.define_singleton_method(:enqueue_start) do
      { ok: true, stage: "researching_outline", message: "Queued outline research." }
    end

    CourseOutlineResearchAsyncService.stub(:new, ->(**kwargs) {
      captured_kwargs = kwargs
      fake_async_service
    }) do
      assert_difference "Message.count", 1 do
        service.execute_tool_call(
          id: "tc-research-outline",
          name: "Generate_Course_Outline",
          arguments: { course_id: course.id, action: "research_outline" }.to_json
        )
      end
    end

    assert_equal course, captured_kwargs[:course]
    assert_equal users(:admin), captured_kwargs[:current_user]
    assert_equal "teacher_chat_tool", captured_kwargs[:source]
    assert_equal conversation.id, captured_kwargs[:conversation_id]

    content = Message.order(:created_at).last.content.to_s
    assert_includes content, "\"status\": \"queued\""
    assert_includes content, "\"action\": \"research_outline\""
    assert_includes content, "\"course_id\": #{course.id}"
    assert_includes content, "teacher will be notified in chalkboard"
    refute_includes content, "\"next_step\""
  end

  test "generate_course_outline action generate_and_research generates then queues research" do
    create_generate_course_outline_tool!
    conversation = conversations(:teacher_generic_conversation)
    course = courses(:one)
    service = ToolExecutionService.new(conversation: conversation, message: nil)

    generated = false
    fake_async_service = Object.new
    fake_async_service.define_singleton_method(:enqueue_start) do
      { ok: true, stage: "researching_outline", message: "Queued outline research." }
    end

    GenerateCourseOutlineJob.stub(:perform_now, ->(*_args) { generated = true }) do
      CourseOutlineResearchAsyncService.stub(:new, ->(**_kwargs) { fake_async_service }) do
        assert_difference "Message.count", 1 do
          service.execute_tool_call(
            id: "tc-generate-and-research",
            name: "Generate_Course_Outline",
            arguments: { course_id: course.id, action: "generate_and_research" }.to_json
          )
        end
      end
    end

    assert_equal true, generated
    content = Message.order(:created_at).last.content.to_s
    assert_includes content, "\"status\": \"ok\""
    assert_includes content, "\"action\": \"generate_and_research\""
    assert_includes content, "\"research_status\": \"queued\""
  end

  private

  def create_show_on_chalkboard_tool!
    tool = Tool.find_or_initialize_by(name: "Show_On_Chalkboard")
    tool.access = :student
    tool.specifications = {
      "name" => "Show_On_Chalkboard",
      "description" => "Displays lesson resources on the chalkboard. Provide exactly one argument: either a URL or a resource_id.",
      "strict_mode" => false,
      "parameters" => {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "description" => "URL to display." },
          "resource_id" => { "type" => "string", "description" => "Resource ID to display." }
        },
        "additionalProperties" => false
      }
    }
    tool.save!
  end

  def create_generate_lesson_plan_tool!
    tool = Tool.find_or_initialize_by(name: "Generate_Lesson_Plan")
    tool.access = :admin
    tool.specifications = {
      "name" => "Generate_Lesson_Plan",
      "description" => "Generate lesson plan content or queue async pipeline actions.",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "lesson_id" => { "type" => "integer", "description" => "ID of the lesson" },
          "action" => { "type" => "string", "description" => "Action", "enum" => [ "generate_content", "propose_resources_async", "generate_content_and_propose_resources_async" ] }
        },
        "required" => [ "lesson_id", "action" ],
        "additionalProperties" => false
      }
    }
    tool.save!
  end

  def create_generate_course_outline_tool!
    tool = Tool.where("LOWER(name) = LOWER(?)", "Generate_Course_Outline").first_or_initialize
    tool.access = :admin
    tool.specifications = {
      "name" => "Generate_Course_Outline",
      "description" => "Generate and/or research a course outline.",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "course_id" => { "type" => "integer", "description" => "ID of the course" },
          "action" => {
            "type" => "string",
            "description" => "Action",
            "enum" => [ "generate_outline", "research_outline", "generate_and_research" ]
          }
        },
        "required" => [ "course_id", "action" ],
        "additionalProperties" => false
      }
    }
    tool.save!
  end

  def create_web_tool!
    tool = Tool.find_or_initialize_by(name: "Web")
    tool.access = :admin
    tool.specifications = {
      "name" => "Web",
      "description" => "Search and retrieve web-grounded information.",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "action" => { "type" => "string", "description" => "Action", "enum" => [ "search", "answer", "content" ] },
          "query" => { "type" => "string", "description" => "Query" },
          "urls" => { "type" => "array", "description" => "URLs", "items" => { "type" => "string" } },
          "num_results" => { "type" => "integer", "description" => "Search result count" }
        },
        "required" => [ "action" ],
        "additionalProperties" => false
      }
    }
    tool.save!
  end
end
