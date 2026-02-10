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

  test "execute_chalkboard_url renders iframe tab for embeddable URL" do
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
    counters = []

    UrlEmbeddabilityService.stub(:check, embed_result) do
      service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
        service.stub(:increment_chalkboard_url_counter!, ->(key) { counters << key }) do
          assert_difference "Message.count", 1 do
            service.send(:execute_chalkboard_url)
          end
        end
      end
    end

    assert_equal "shared/chalkboard_iframe", broadcast_args[:partial]
    assert_equal({ url: "https://example.com/embeddable" }, broadcast_args[:locals])
    assert_equal [ "chalkboard_url.embed_success" ], counters
    assert_includes Message.order(:created_at).last.content, "[Open link](https://example.com/embeddable)"
  end

  test "execute_chalkboard_url renders fallback tab for x-frame blocked URL" do
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
    counters = []

    UrlEmbeddabilityService.stub(:check, embed_result) do
      service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
        service.stub(:increment_chalkboard_url_counter!, ->(key) { counters << key }) do
          assert_difference "Message.count", 1 do
            service.send(:execute_chalkboard_url)
          end
        end
      end
    end

    assert_equal "shared/chalkboard_link_fallback", broadcast_args[:partial]
    assert_equal "Site blocks embedding via X-Frame-Options.", broadcast_args.dig(:locals, :reason)
    assert_equal [ "chalkboard_url.fallback_blocked" ], counters
    assert_includes Message.order(:created_at).last.content, "blocks iframe embedding"
  end

  test "execute_chalkboard_url keeps iframe attempt and adds markdown link when embeddability is unknown" do
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
    counters = []

    UrlEmbeddabilityService.stub(:check, embed_result) do
      service.stub(:broadcast_chalkboard_push_tab, ->(**kwargs) { broadcast_args = kwargs }) do
        service.stub(:increment_chalkboard_url_counter!, ->(key) { counters << key }) do
          assert_difference "Message.count", 1 do
            service.send(:execute_chalkboard_url)
          end
        end
      end
    end

    assert_equal "shared/chalkboard_iframe", broadcast_args[:partial]
    assert_equal [ "chalkboard_url.embed_unknown" ], counters
    assert_includes Message.order(:created_at).last.content, "Embeddability check was inconclusive"
    assert_includes Message.order(:created_at).last.content, "[Open link](https://example.com/unknown)"
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

  private

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
end
