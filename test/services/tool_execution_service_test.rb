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
end
