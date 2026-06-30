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
      assert_selector "html[data-goa-applet-shell='v1']", visible: :all, wait: 1
      assert_selector "h1", text: "Inline Applet Output", wait: 1
      assert_selector "div.console-log span", text: "console log!", wait: 1
    end
  end

  test "applet shell template is available before initial executable code blocks" do
    Message.create!(
      conversation: @conversation,
      role: :assistant,
      content: <<~HTML
        ```javascript {executable="true" renderTarget="chalkboard" autoRun="true"}
        document.getElementById("sandbox").innerHTML = "<h2>Initial Applet Output</h2>";
        ```
      HTML
    )

    visit conversation_path(@conversation)

    assert_selector "#goa-applet-shell-template", visible: :all
    assert_selector "[data-controller~=\"code-executor\"]", visible: :all
    shell_precedes_executable = evaluate_script(<<~JS)
      document.getElementById("goa-applet-shell-template")
        .compareDocumentPosition(document.querySelector('[data-controller~="code-executor"]')) &
        Node.DOCUMENT_POSITION_FOLLOWING
    JS

    assert_operator shell_precedes_executable, :>, 0

    iframe = find("#chalkboard iframe", visible: true)
    within_frame(iframe) do
      assert_selector "html[data-goa-applet-shell=\"v1\"]", visible: :all, wait: 1
      assert_selector "h2", text: "Initial Applet Output", wait: 10
    end
  end

  test "turbo navigation to conversation with initial auto-run applet has shell template" do
    destination = Conversation.create!(
      user: @admin,
      title: "Turbo Applet Destination",
      task_system_prompt: "Test prompt"
    )
    Message.create!(
      conversation: destination,
      role: :assistant,
      content: <<~HTML
        ```javascript {executable="true" renderTarget="chalkboard" autoRun="true"}
        document.getElementById("sandbox").innerHTML = "<h2>Turbo Navigation Applet Output</h2>";
        ```
      HTML
    )

    visit conversation_path(@conversation)
    click_link "Turbo Applet Destination"

    assert_current_path conversation_path(destination)
    iframe = find("#chalkboard iframe", visible: true)
    within_frame(iframe) do
      assert_selector "html[data-goa-applet-shell=\"v1\"]", visible: :all, wait: 1
      assert_selector "h2", text: "Turbo Navigation Applet Output", wait: 10
    end
  end

  test "auto-run waits when applet shell template is temporarily unavailable" do
    visit conversation_path(@conversation)

    execute_script <<~JS
      const shell = document.getElementById("goa-applet-shell-template");
      shell.remove();
      setTimeout(() => document.body.prepend(shell), 1000);
    JS

    message = Message.create!(
      conversation: @conversation,
      role: :assistant,
      content: <<~HTML
        ```javascript {executable="true" renderTarget="chalkboard" autoRun="true"}
        document.getElementById("sandbox").innerHTML = "<h2>Delayed Shell Applet Output</h2>";
        ```
      HTML
    )
    execute_script <<~JS
      window.__goaCompletedAssistantMessageIds ||= new Set();
      window.__goaCompletedAssistantMessageIds.add("#{message.id}");
    JS

    perform_enqueued_jobs do
      message.broadcast_created
    end

    iframe = find("#chalkboard iframe", visible: true, wait: 10)
    within_frame(iframe) do
      assert_selector "html[data-goa-applet-shell=\"v1\"]", visible: :all, wait: 1
      assert_selector "h2", text: "Delayed Shell Applet Output", wait: 10
    end
  end

  test "error shell fallback does not mark auto-run applet executed" do
    ignore_browser_console_logs_matching(/Applet shell template not found\./)

    visit conversation_path(@conversation)

    execute_script <<~JS
      window.__removedAppletShell = document.getElementById("goa-applet-shell-template");
      window.__removedAppletShell.remove();
    JS

    message = Message.create!(
      conversation: @conversation,
      role: :assistant,
      content: <<~HTML
        ```javascript {executable="true" renderTarget="chalkboard" autoRun="true"}
        document.getElementById("sandbox").innerHTML = "<h2>Recovered Applet Output</h2>";
        ```
      HTML
    )
    execute_script <<~JS
      window.__goaCompletedAssistantMessageIds ||= new Set();
      window.__goaCompletedAssistantMessageIds.add("#{message.id}");
    JS

    perform_enqueued_jobs do
      message.broadcast_created
    end

    iframe = find("#chalkboard iframe", visible: true, wait: 10)
    within_frame(iframe) do
      assert_selector "html[data-goa-applet-shell-error=\"missing-template\"]", visible: :all, wait: 5
    end

    assert_empty evaluate_script("Array.from(window.__goaAutoRunAppletKeys || [])")
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

  test "chalkboard generated applet shell follows dark mode" do
    visit conversation_path(@conversation)
    enable_dark_mode_for_page

    message_content = <<~HTML
      ```javascript {executable="true" renderTarget="chalkboard" autoRun="true"}
      document.getElementById('sandbox').innerHTML = '<h2>Dark Chalkboard Applet Output</h2>';
      ```
    HTML

    perform_enqueued_jobs do
      message = Message.create!(conversation: @conversation, role: :assistant, content: message_content)
      message.broadcast_created
    end

    iframe = find("#chalkboard iframe", visible: true)
    assert_equal "rgb(28, 25, 23)", iframe_background_color

    within_frame(iframe) do
      assert_selector "html[data-goa-applet-shell='v1']", visible: :all, wait: 1
      assert_selector "h2", text: "Dark Chalkboard Applet Output", wait: 10
      assert_equal true, evaluate_script("document.documentElement.classList.contains('dark')")
      assert_equal "rgb(28, 25, 23)", evaluate_script("getComputedStyle(document.body).backgroundColor")
    end
  end

  test "saved applet runs on chalkboard from registered run url" do
    applet = Applet.create!(
      user: @admin,
      title: "Saved Chalkboard Applet",
      code: "document.getElementById('sandbox').innerHTML = '<h2>Saved Chalkboard Applet Output</h2>';"
    )

    visit conversation_path(@conversation)

    execute_script <<~JS
      window.dispatchEvent(new CustomEvent("chalkboard:register-applet", {
        detail: {
          event_type: "register_applet",
          source: "linked",
          key: "linked_#{applet.id}",
          applet_id: #{applet.id},
          title: "Saved Chalkboard Applet",
          launch_url: "#{run_applet_path(applet)}",
          embed_src: "#{run_applet_path(applet)}",
          embed_srcdoc: null,
          shareable: true,
          share_url: "#{run_applet_path(applet)}",
          auto_open_in_board: true
        }
      }));
    JS

    iframe = find("#panel-applets iframe", visible: true)
    within_frame(iframe) do
      assert_selector "html[data-goa-applet-shell='v1']", visible: :all, wait: 1
      assert_selector "h2", text: "Saved Chalkboard Applet Output", wait: 10
    end
  end

  test "saved applet launched on dark chalkboard receives dark shell" do
    applet = Applet.create!(
      user: @admin,
      title: "Saved Dark Chalkboard Applet",
      code: "document.getElementById('sandbox').innerHTML = '<h2>Saved Dark Chalkboard Applet Output</h2>';"
    )

    visit conversation_path(@conversation)
    enable_dark_mode_for_page

    execute_script <<~JS
      window.dispatchEvent(new CustomEvent("chalkboard:register-applet", {
        detail: {
          event_type: "register_applet",
          source: "linked",
          key: "linked_dark_#{applet.id}",
          applet_id: #{applet.id},
          title: "Saved Dark Chalkboard Applet",
          launch_url: "#{run_applet_path(applet)}",
          embed_src: "#{run_applet_path(applet)}",
          embed_srcdoc: null,
          shareable: true,
          share_url: "#{run_applet_path(applet)}",
          auto_open_in_board: true
        }
      }));
    JS

    iframe = find("#panel-applets iframe", visible: true)
    assert_includes iframe[:src], "theme=dark"
    assert_equal "rgb(28, 25, 23)", iframe_background_color("#panel-applets iframe")

    within_frame(iframe) do
      assert_selector "html[data-goa-applet-shell='v1']", visible: :all, wait: 1
      assert_selector "h2", text: "Saved Dark Chalkboard Applet Output", wait: 10
      assert_equal true, evaluate_script("document.documentElement.classList.contains('dark')")
      assert_equal "rgb(28, 25, 23)", evaluate_script("getComputedStyle(document.body).backgroundColor")
    end

    execute_script <<~JS
      const iframe = document.querySelector("#panel-applets iframe");
      iframe.src = iframe.src.replace("theme=dark", "theme=light");
    JS

    iframe = find("#panel-applets iframe", visible: true)
    assert_includes iframe[:src], "theme=light"
    within_frame(iframe) do
      assert_selector "h2", text: "Saved Dark Chalkboard Applet Output", wait: 10
      assert_selector "html.dark", visible: :all, wait: 5
      assert_equal "rgb(28, 25, 23)", evaluate_script("getComputedStyle(document.body).backgroundColor")
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

  private

  def enable_dark_mode_for_page
    page.execute_script(<<~JS)
      localStorage.theme = 'dark';
      document.documentElement.classList.add('dark', 'sl-theme-dark', 'wa-dark');
      window.dispatchEvent(new CustomEvent('goa:theme-change', { detail: { theme: 'dark' } }));
    JS
  end

  def iframe_background_color(selector = "#chalkboard iframe")
    evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json})).backgroundColor")
  end
end
