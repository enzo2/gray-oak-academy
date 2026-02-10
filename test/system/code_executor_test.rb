require "application_system_test_case"

class CodeExecutorTest < ApplicationSystemTestCase
  def setup
    @admin = users(:admin)
    sign_in @admin
    @conversation = conversations(:teacher_generic_conversation)
  end

  test "executable javascript code block runs inline and shows output" do
    visit conversation_path(@conversation)

    # Simulate LLM sending a message with an executable code block
    message_content = <<~HTML
      ```javascript {executable="true" renderTarget="inline" autoRun="true"}
      document.getElementById('sandbox').innerHTML = '<h1>Inline Applet Output</h1>';
      console.log('console log!');
      ```
    HTML

    # Manually create the message and broadcast it to simulate the LLM response
    # This bypasses the GetLlmCompletionJob and directly renders the message
    message = nil
    perform_enqueued_jobs do
      message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
      message.broadcast_created # Manually trigger the broadcast
    end

    # Wait for the message to appear and the applet to run
    iframe = find("#message_#{message.id}_content iframe", visible: true)
    within_frame(iframe) do
      assert_selector "h1", text: "Inline Applet Output", wait: 1
      assert_selector "div.console-log span", text: "console log!", wait: 1
    end
  end

  test "executable javascript code block runs on chalkboard" do
    visit conversation_path(@conversation)

    # Simulate LLM sending a message with an executable code block for chalkboard
    message_content = <<~HTML
      ```javascript {executable="true" renderTarget="chalkboard" autoRun="true"}
      document.getElementById('sandbox').innerHTML = '<h2>Chalkboard Applet Output</h2>';
      ```
    HTML

    message = nil
    perform_enqueued_jobs do
      message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
      message.broadcast_created
    end

    # Wait for the chalkboard content to appear
    iframe = find("#chalkboard iframe", visible: true)
    within_frame(iframe) do
      assert_selector "h2", text: "Chalkboard Applet Output", wait: 10
    end
  end

  test "chalkboard tabs preserve whiteboard and applet iframes and jit applet share stays hidden" do
    visit conversation_path(@conversation)

    message_content = <<~HTML
      ```javascript {executable="true" renderTarget="chalkboard" autoRun="false"}
      document.getElementById('sandbox').innerHTML = '<h2>JIT Chalkboard Applet</h2>';
      ```
    HTML

    perform_enqueued_jobs do
      message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
      message.broadcast_created
    end

    click_on "Run"
    assert_selector "#panel-applets iframe", visible: true

    find("#chalkboard-tab-applets").click
    assert_selector "#chalkboard-applet-select option", minimum: 2
    execute_script <<~JS
      const select = document.getElementById("chalkboard-applet-select");
      select.selectedIndex = 1;
      select.dispatchEvent(new Event("change", { bubbles: true }));
    JS

    assert_selector "#panel-applets iframe", visible: true
    applet_cache_key = evaluate_script("document.querySelector('#panel-applets iframe')?.dataset?.chalkboardCacheKey")
    assert applet_cache_key.present?
    assert_equal true, evaluate_script("document.getElementById('chalkboard-share-applet').classList.contains('hidden')")

    find("#chalkboard-tab-whiteboard").click
    assert_selector "#panel-whiteboard iframe", visible: true
    whiteboard_cache_key = evaluate_script("document.querySelector('#panel-whiteboard iframe')?.dataset?.chalkboardCacheKey")
    assert_equal "whiteboard", whiteboard_cache_key

    find("#chalkboard-tab-applets").click
    assert_selector "#panel-applets iframe", visible: true
    assert_equal applet_cache_key, evaluate_script("document.querySelector('#panel-applets iframe')?.dataset?.chalkboardCacheKey")
  end

  test "executable javascript code block is hidden and can be shown/hidden" do
    visit conversation_path(@conversation)

    message_content = <<~HTML
      ```javascript {executable="true" hidden="true" renderTarget="inline" autoRun="false"}
      console.log('Hidden applet!');
      ```
    HTML

    message = nil
    perform_enqueued_jobs do
      message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
      message.broadcast_created
    end

    # Ensure code block is initially hidden
    assert_no_selector "#message_#{message.id}_content .highlighted-code-block", visible: true
    assert_selector "button", text: "Show Code"

    # Click "Show Code"
    click_on "Show Code"
    assert_selector "#message_#{message.id}_content .highlighted-code-block", visible: true
    assert_selector "button", text: "Hide Code"

    # Click "Hide Code"
    click_on "Hide Code"
    assert_no_selector "#message_#{message.id}_content .highlighted-code-block", visible: true
    assert_selector "button", text: "Show Code"
  end

  test "executable javascript code block runs on button click" do
    visit conversation_path(@conversation)

    message_content = <<~HTML
      ```javascript {executable="true" renderTarget="inline" autoRun="false"}
      document.getElementById('sandbox').innerHTML = '<h3>Clicked Applet Output</h3>';
      ```
    HTML

    message = nil
    perform_enqueued_jobs do
      message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
      message.broadcast_created
    end

    # Ensure output is not present initially
    assert_no_selector "#message_#{message.id}_content iframe", visible: true

    # Click "Run" button
    click_on "Run"
    iframe = find("#message_#{message.id}_content iframe", visible: true)
    within_frame(iframe) do
      assert_selector "h3", text: "Clicked Applet Output", wait: 10
    end
  end
end
