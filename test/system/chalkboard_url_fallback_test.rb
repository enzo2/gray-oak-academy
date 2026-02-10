require "application_system_test_case"

class ChalkboardUrlFallbackTest < ApplicationSystemTestCase
  test "blocked URL opens chalkboard fallback tab with direct-link action" do
    admin = users(:admin)
    conversation = conversations(:teacher_generic_conversation)
    sign_in admin
    visit conversation_path(conversation)

    embed_result = {
      status: "blocked_xfo",
      reason: "Site blocks embedding via X-Frame-Options.",
      final_url: "https://example.com/blocked",
      x_frame_options: "SAMEORIGIN",
      csp_frame_ancestors: nil
    }

    UrlEmbeddabilityService.stub(:check, embed_result) do
      service = ToolExecutionService.new(conversation: conversation, message: nil)
      service.instance_variable_set(:@tool_call_id, "tc-system-fallback-1")
      service.instance_variable_set(:@args, { "url" => "https://example.com/blocked" })
      service.send(:execute_chalkboard_url)
    end

    assert_selector "#chalkboard", text: "Open Resource In New Tab", wait: 5
    assert_selector "#chalkboard", text: "This site did not allow embedding inside the chalkboard.", wait: 5
    assert_link "Open in new tab", href: "https://example.com/blocked"
  end
end
