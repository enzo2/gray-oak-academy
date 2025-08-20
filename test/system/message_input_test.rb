require "application_system_test_case"
require "uri"

class MessageInputTest < ApplicationSystemTestCase
  def setup
    @student = users(:student)
    sign_in @student
    @conversation = conversations(:student_generic_conversation)
  end

  # Helper to fill Shoelace sl-textarea (or fallback native textarea/input)
  def fill_message_content(text)
    page.execute_script(<<~JS, text)
      const value = arguments[0];
      const el = document.querySelector('sl-textarea[name="message[content]"]');
      // Update the custom element's value (important so Stimulus sees the change)
      if (el) {
        try { el.value = value; } catch (e) { /* ignore if not writable */ }
        el.dispatchEvent(new Event('input', { bubbles: true }));
      }
      // Also update the native textarea inside the shadow root (visual parity)
      const ta = el?.shadowRoot?.querySelector('textarea');
      if (ta) {
        ta.value = value;
        ta.dispatchEvent(new Event('input', { bubbles: true }));
      } else {
        const native = document.querySelector('textarea[name="message[content]"], input[name="message[content]"]');
        if (native) {
          native.value = value;
          native.dispatchEvent(new Event('input', { bubbles: true }));
        }
      }
    JS
  end

  # Helper to fill Shoelace sl-input by placeholder (used for URL dialog)
  def fill_sl_input_by_placeholder(placeholder, value)
    page.execute_script(<<~JS, placeholder, value)
      const placeholder = arguments[0];
      const value = arguments[1];
      const el = document.querySelector(`sl-input[placeholder="${placeholder}"]`) || document.querySelector(`[placeholder="${placeholder}"]`);
      const input = el?.shadowRoot?.querySelector('input') || el;
      if (input) {
        input.value = value;
        input.dispatchEvent(new Event('input', { bubbles: true }));
      }
    JS
  end

  test "sending a text message" do
    visit conversation_path(@conversation)
    fill_message_content "Testing"
    find('button[data-new-message-target="submitButton"]').click

    # First, wait for the text to appear on the page. This confirms the async job and broadcast have completed.
    assert_text "Testing", wait: 5

    # Now that the UI is updated, the database state should also be correct.
    assert_equal "Testing", @conversation.reload.messages.last.content
  end

  test "sending a message with image attachment via file input" do
    visit conversation_path(@conversation)

    # Click the images menu button
    find('sl-icon-button[name="images"]').click
    # Click "Upload Image"
    find('sl-menu-item[value="file"]').click

    # Attach a dummy image file
    find('input[data-new-message-target="fileInput"]', visible: false).attach_file(Rails.root.join("test/fixtures/files/sample.png"))

    # Wait for the preview to show the image (FileReader is async)
    assert_selector '#previewArea img[alt="Image 1"]', wait: 2

    # Type a message
    fill_message_content "Here's an image!"

    # Submit the form
    find('button[data-new-message-target="submitButton"]').click

    # Wait for the message and image to appear
    assert_selector ".message-content img[alt='Image 1']", wait: 2, visible: :all
    assert_text "Here's an image!"
  end

  test "sending a message with image attachment via URL" do
    visit conversation_path(@conversation)

    # Click the images menu button
    find('sl-icon-button[name="images"]').click
    # Click "Link to URL"
    find('sl-menu-item[value="url"]').click

    # Fill in the URL dialog
    # Use a local test image served by the Rails test server to avoid external network issues.
    base = URI.parse(page.current_url)
    local_url = "#{base.scheme}://#{base.host}:#{base.port}/test_images/sample.png"
    fill_sl_input_by_placeholder("Enter full image URL (https://...)", local_url)
    find("sl-button", text: "Submit").click

    # Wait for the preview to show the image (proxy HEAD check and FileReader are async)
    assert_selector '#previewArea img[alt="Image 1"]', wait: 10

    # Type a message
    fill_message_content "Here's an image from URL!"

    # Submit the form
    find('button[data-new-message-target="submitButton"]').click

    # Wait for the message and image to appear
    assert_selector ".message-content img[alt='Image 1']", wait: 2, visible: :all
    assert_text "Here's an image from URL!"
  end

  test "pasting an image into the message input" do
    visit conversation_path(@conversation)
    # Explicitly wait for the content field to be present
    content_field = page.find('sl-textarea[data-new-message-target="contentField"]', wait: 2)

    # Simulate pasting an image by dispatching a paste event
    page.execute_script(<<~JS, content_field)
      const targetElement = arguments[0];
      const data = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
      const blob = await fetch(data).then(res => res.blob());
      const file = new File([blob], 'pasted_image.png', { type: 'image/png' });
      const dataTransfer = new DataTransfer();
      dataTransfer.items.add(file);

      const pasteEvent = new ClipboardEvent('paste', {
        clipboardData: dataTransfer,
        bubbles: true,
        cancelable: true
      });
      targetElement.dispatchEvent(pasteEvent);
    JS

    # Wait for preview to show the pasted image
    assert_selector '#previewArea img[alt="Image 1"]', wait: 2

    # Type a message
    fill_message_content "Pasted image here!"

    # Submit the form
    find('button[data-new-message-target="submitButton"]').click

    # Wait for the message and image to appear
    assert_selector ".message-content img[alt='Image 1']", wait: 2, visible: :all
    assert_text "Pasted image here!"
  end

  test "removing an image from the preview area" do
    visit conversation_path(@conversation)

    # Add an image first
    find('sl-icon-button[name="images"]').click
    sleep 0.05 # Allow menu to open
    find('sl-menu-item[value="file"]').click
    # Attach a dummy image file
    find('input[data-new-message-target="fileInput"]', visible: false, wait: 20).attach_file(Rails.root.join("test/fixtures/files/sample.png"))

    # Ensure image is in preview
    find("#previewArea", wait: 2) # Ensure the preview area itself is visible
    assert_selector "#previewArea img[src^='data:image']", count: 1, wait: 2 # Check for data URL source

    # Click the remove button (x icon)
    find('#previewArea sl-icon-button[name="x"]').click

    # Assert image is removed from preview
    assert_no_selector "#previewArea img", wait: 2
    assert_selector "#previewArea.hidden", visible: :all, wait: 2
  end
end
