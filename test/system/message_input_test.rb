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

  def submit_url_dialog
    # Click the Submit button in the dialog
    page.execute_script(<<~JS)
      const event = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'Enter' });
      document.querySelector("sl-dialog[data-new-message-target='urlDialog']").querySelector('sl-input').dispatchEvent(event);
    JS
  end

  def stub_camera!
    page.execute_script(<<~JS)
      try {
        Object.defineProperty(window, 'isSecureContext', { value: true, configurable: true });
      } catch (e) {}

      const fakeDevices = [{ kind: 'videoinput', deviceId: 'test-device', label: 'Front Camera' }];
      const fakeStream = new MediaStream();
      const mediaDevices = {
        enumerateDevices: () => Promise.resolve(fakeDevices),
        getUserMedia: () => Promise.resolve(fakeStream)
      };

      try {
        Object.defineProperty(navigator, 'mediaDevices', { value: mediaDevices, configurable: true });
      } catch (e) {
        navigator.mediaDevices = mediaDevices;
      }

      // Ensure camera capture doesn't depend on real video frames.
      HTMLMediaElement.prototype.play = () => Promise.resolve();
      HTMLCanvasElement.prototype.getContext = () => ({
        drawImage: () => {},
        save: () => {},
        restore: () => {},
        translate: () => {},
        scale: () => {}
      });
      HTMLCanvasElement.prototype.toBlob = function(callback) {
        callback(new Blob(["x"], { type: "image/jpeg" }));
      };
    JS
  end

  def stub_screenshot_capture_hooks!
    page.execute_script(<<~JS)
      const form = document.querySelector("form[data-controller*='new-message']");
      const controller = window.Stimulus?.getControllerForElementAndIdentifier(form, "new-message");
      if (!controller) return;

      controller.offerBrowserScreenshot = true;
      if (controller.hasScreenshotMenuItemTarget) {
        controller.screenshotMenuItemTarget.classList.remove("hidden");
      }

      controller.captureBrowserScreenshot = () => {
        document.body.dataset.browserScreenshotRequested = "true";
      };
      controller.captureBrowserScreenshotUncropped = () => {
        document.body.dataset.browserScreenshotMenuRequested = "true";
      };
    JS
  end

  test "sending a text message" do
    visit conversation_path(@conversation)
    fill_message_content "Testing"
    assert_equal "Testing", find('sl-textarea[name="message[content]"]').value, wait: 5
    sleep 0.05 # Allow submit button to become enabled
    assert_selector 'button[data-new-message-target="submitButton"]', wait: 5
    find('button[data-new-message-target="submitButton"]').click

    assert_text "Testing", wait: 10

    # Now that the UI is updated, the database state should also be correct.
    assert_equal "Testing", @conversation.reload.messages.last.content
  end

  test "sending a message with image attachment via file input" do
    visit conversation_path(@conversation)

    # Click the images menu button
    find('sl-icon-button[name="images"]').click
    sleep 0.2 # Wait for the menu to open
    assert_selector 'sl-menu-item[value="file"]', visible: true, wait: 5
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
    sleep 0.1 # Wait for the menu to open
    assert_selector 'sl-menu-item[value="url"]', visible: true, wait: 5
    # Click "Link to URL"
    find('sl-menu-item[value="url"]').click
    # sleep 0.2 # Dialog opens
    assert_selector "sl-dialog[data-new-message-target='urlDialog']", wait: 5

    # Fill in the URL dialog
    # Use a local test image served by the Rails test server to avoid external network issues.
    base = URI.parse(page.current_url)
    local_url = "#{base.scheme}://#{base.host}:#{base.port}/test_images/sample.png"
    fill_sl_input_by_placeholder("Enter full image URL (https://...)", local_url)
    validated_response = Net::HTTPOK.new("1.1", "200", "OK")
    validated_response["Content-Type"] = "image/png"
    validated_response["Content-Length"] = "1024"
    safe_request = Object.new
    safe_request.define_singleton_method(:call) { validated_response }

    SafeHttpHeadRequest.stub(:new, ->(*) { safe_request }) do
      submit_url_dialog

      # Wait for the preview to show the image (proxy HEAD check and FileReader are async)
      assert_selector '#previewArea img[alt="Image 1"]', wait: 10
    end
    assert_no_selector "sl-dialog[data-new-message-target='urlDialog'][open]", wait: 5
    sleep 0.5 # Wait for dialog fade-out animation to complete

    # Type a message
    fill_message_content "Here's an image from URL!"

    # Submit the form
    find('button[data-new-message-target="submitButton"]').click

    # Wait for the message and image to appear
    assert_selector ".message-content img[alt='Image 1']", wait: 5, visible: :all
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
    assert_equal "Pasted image here!", find('sl-textarea[name="message[content]"]').value, wait: 5
    sleep 0.1 # Allow submit button to become enabled
    assert_selector 'button[data-new-message-target="submitButton"]', wait: 5
    # Submit the form
    # find('button[data-new-message-target="submitButton"]').click

    # Wait for the message and image to appear
    # assert_selector ".message-content img[alt='Image 1']", wait: 10, visible: :all
    # assert_text "Pasted image here!"
  end

  test "removing an image from the preview area" do
    visit conversation_path(@conversation)

    # Add an image first
    find('sl-icon-button[name="images"]').click
    assert_selector 'sl-menu-item[value="file"]', visible: true, wait: 5
    find('sl-menu-item[value="file"]').click
    # Attach a dummy image file
    find('input[data-new-message-target="fileInput"]', visible: false, wait: 10).attach_file(Rails.root.join("test/fixtures/files/sample.png"))

    # Ensure image is in preview
    find("#previewArea", wait: 2) # Ensure the preview area itself is visible
    assert_selector "#previewArea img[src^='data:image']", count: 1, wait: 2 # Check for data URL source

    # Click the remove button (x icon)
    find('#previewArea sl-icon-button[name="x"]').click

    # Assert image is removed from preview
    assert_no_selector "#previewArea img", wait: 2
    assert_selector "#previewArea.hidden", visible: :all, wait: 2
  end

  test "audio-only lessons show camera action in image menu when available" do
    @conversation = conversations(:student_audio_only_conversation)
    visit conversation_path(@conversation)

    stub_camera!

    page.execute_script(<<~JS)
      document.dispatchEvent(new CustomEvent('new-message:camera-check', { bubbles: true }));
    JS

    assert_selector "sl-menu-item[value='camera']:not(.hidden)", visible: :all, wait: 5
  end

  test "audio-only lessons can capture a photo and attach it from image menu" do
    @conversation = conversations(:student_audio_only_conversation)
    visit conversation_path(@conversation)

    stub_camera!

    page.execute_script(<<~JS)
      document.dispatchEvent(new CustomEvent('new-message:camera-check', { bubbles: true }));
    JS

    assert_selector "sl-menu-item[value='camera']:not(.hidden)", visible: :all, wait: 5
    find('sl-icon-button[name="images"]').click
    find("sl-menu-item[value='camera']", visible: true, wait: 5).click

    assert_selector "sl-button[data-camera-target='captureButton']", wait: 5
    page.execute_script(<<~JS)
      const video = document.querySelector('[data-camera-target="video"]');
      if (video) {
        Object.defineProperty(video, 'videoWidth', { value: 640, configurable: true });
        Object.defineProperty(video, 'videoHeight', { value: 480, configurable: true });
      }
    JS

    assert_equal false, page.evaluate_script("document.querySelector('[data-camera-target=\"captureButton\"]').disabled")
    find("sl-button[data-camera-target='captureButton']").click

    assert_selector "img[data-camera-target='preview']:not(.hidden)", visible: :all, wait: 5
    assert_selector "sl-button[data-camera-target='useButton']:not(.hidden)", visible: :all, wait: 5
    find("sl-button[data-camera-target='useButton']").click

    assert_selector "#previewArea img", wait: 5
  end

  test "chalkboard screenshot instructions can trigger browser screenshot capture" do
    visit conversation_path(@conversation)
    stub_screenshot_capture_hooks!

    find("#screenshotButton").click
    assert_text "Chalkboard screenshot instructions", wait: 5

    find("button[data-modal-close-reason='browser-screenshot']", visible: true, wait: 5).click
    assert_selector "body[data-browser-screenshot-requested='true']", wait: 5
  end

  test "images menu screenshot action triggers uncropped browser screenshot capture" do
    visit conversation_path(@conversation)
    stub_screenshot_capture_hooks!

    find('sl-icon-button[name="images"]').click
    find("sl-menu-item[value='screenshot']", visible: true, wait: 5).click

    assert_selector "body[data-browser-screenshot-menu-requested='true']", wait: 5
  end
end
