require "application_system_test_case"

class CodeExecutorTest < ApplicationSystemTestCase
  def setup
    @admin = users(:admin)
    sign_in @admin
    @conversation = conversations(:admin_conversation)
  end

  test "executable javascript code block runs inline and shows output" do
    visit conversation_path(@conversation)

    # Simulate LLM sending a message with an executable code block
    message_content = <<~HTML
      ```javascript {executable="true" renderTarget="inline" autoRun="true"}
      console.log('Hello from inline applet!');
      document.getElementById('sandbox').innerHTML = '<h1>Inline Applet Output</h1>';
      ```
    HTML

    # Manually create the message and broadcast it to simulate the LLM response
    # This bypasses the GetLlmCompletionJob and directly renders the message
    message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
    message.broadcast_created # Manually trigger the broadcast

    # Wait for the message to appear and the applet to run
    assert_selector "#message_#{message.id}_content h1", text: "Inline Applet Output", wait: 10
    assert_selector "#message_#{message.id}_content div", text: "Hello from inline applet!", wait: 10
  end

  test "executable javascript code block runs on chalkboard" do
    visit conversation_path(@conversation)

    # Simulate LLM sending a message with an executable code block for chalkboard
    message_content = <<~HTML
      ```javascript {executable="true" renderTarget="chalkboard" autoRun="true"}
      document.getElementById('sandbox').innerHTML = '<h2>Chalkboard Applet Output</h2>';
      ```
    HTML

    message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
    message.broadcast_created

    # Wait for the chalkboard content to appear
    assert_selector "#chalkboard h2", text: "Chalkboard Applet Output", wait: 10
  end

  test "executable javascript code block is hidden and can be shown/hidden" do
    visit conversation_path(@conversation)

    message_content = <<~HTML
      ```javascript {executable="true" hidden="true" renderTarget="inline" autoRun="false"}
      console.log('Hidden applet!');
      ```
    HTML

    message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
    message.broadcast_created

    # Ensure code block is initially hidden
    assert_no_selector "#message_#{message.id}_content pre.highlighted-code-block", visible: true
    assert_selector "button", text: "Show Code"

    # Click "Show Code"
    click_on "Show Code"
    assert_selector "#message_#{message.id}_content pre.highlighted-code-block", visible: true
    assert_selector "button", text: "Hide Code"

    # Click "Hide Code"
    click_on "Hide Code"
    assert_no_selector "#message_#{message.id}_content pre.highlighted-code-block", visible: true
    assert_selector "button", text: "Show Code"
  end

  test "executable javascript code block runs on button click" do
    visit conversation_path(@conversation)

    message_content = <<~HTML
      ```javascript {executable="true" renderTarget="inline" autoRun="false"}
      document.getElementById('sandbox').innerHTML = '<h3>Clicked Applet Output</h3>';
      ```
    HTML

    message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
    message.broadcast_created

    # Ensure output is not present initially
    assert_no_selector "#message_#{message.id}_content h3", text: "Clicked Applet Output"

    # Click "Run" button
    click_on "Run"
    assert_selector "#message_#{message.id}_content h3", text: "Clicked Applet Output", wait: 10
  end
end
