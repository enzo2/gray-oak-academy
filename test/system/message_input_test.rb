require "application_system_test_case"

class MessageInputTest < ApplicationSystemTestCase
  def setup
    @student = users(:student)
    sign_in @student
    @conversation = conversations(:student_conversation)
  end

  test "sending a message with image attachment via file input" do
    visit conversation_path(@conversation)

    # Click the images menu button
    find('sl-icon-button[name="images"]').click
    # Click "Upload Image"
    find('sl-menu-item[value="file"]').click

    # Attach a dummy image file
    attach_file("message_images[]", Rails.root.join("test/fixtures/files/sample.png"), make_visible: true)

    # Type a message
    fill_in "message[content]", with: "Here's an image!"

    # Submit the form
    click_button "arrow-right-square"

    # Wait for the message and image to appear
    assert_selector ".message-content img[alt='Image 1']", wait: 10
    assert_text "Here's an image!"
  end

  test "sending a message with image attachment via URL" do
    visit conversation_path(@conversation)

    # Click the images menu button
    find('sl-icon-button[name="images"]').click
    # Click "Link to URL"
    find('sl-menu-item[value="url"]').click

    # Fill in the URL dialog
    fill_in "Enter full image URL (https://...)", with: "http://example.com/test.png"
    click_button "Submit"

    # Type a message
    fill_in "message[content]", with: "Here's an image from URL!"

    # Submit the form
    click_button "arrow-right-square"

    # Wait for the message and image to appear
    assert_selector ".message-content img[src='http://example.com/test.png']", wait: 10
    assert_text "Here's an image from URL!"
  end

  test "pasting an image into the message input" do
    visit conversation_path(@conversation)

    # Simulate pasting an image (Capybara doesn't directly support paste events with image data)
    # We'll simulate the effect by calling the Stimulus controller method directly
    page.evaluate_script("
      const controller = document.querySelector('[data-controller=\"new-message\"]')._stimulusControllers[0];
      const blob = new Blob(['fake image data'], { type: 'image/png' });
      const file = new File([blob], 'pasted_image.png', { type: 'image/png' });
      controller.addImage(file);
    ")

    # Type a message
    fill_in "message[content]", with: "Pasted image here!"

    # Submit the form
    click_button "arrow-right-square"

    # Wait for the message and image to appear
    assert_selector ".message-content img[alt='Image 1']", wait: 10
    assert_text "Pasted image here!"
  end

  test "removing an image from the preview area" do
    visit conversation_path(@conversation)

    # Add an image first
    find('sl-icon-button[name="images"]').click
    find('sl-menu-item[value="file"]').click
    attach_file("message_images[]", Rails.root.join("test/fixtures/files/sample.png"), make_visible: true)

    # Ensure image is in preview
    assert_selector ".preview-area img", count: 1

    # Click the remove button (x icon)
    find('.preview-area sl-icon-button[name="x"]').click

    # Assert image is removed from preview
    assert_no_selector ".preview-area img"
    assert_selector ".preview-area.hidden"
  end
end
