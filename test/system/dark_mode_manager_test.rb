require "application_system_test_case"

class DarkModeManagerTest < ApplicationSystemTestCase
  def setup
    @student = users(:student)
    sign_in @student
    @conversation = conversations(:student_generic_conversation)
  end

  test "dark mode initialization tolerates missing toggle button" do
    visit conversation_path(@conversation)

    page.execute_script(<<~JS)
      window.__darkModeErrors = [];
      window.addEventListener('error', (event) => {
        window.__darkModeErrors.push(event.message || String(event.error || 'unknown error'));
      });
    JS

    # Clear any prior console output.
    console_logs

    page.execute_script(<<~JS)
      const toggle = document.querySelector('.dark-mode-toggle');
      if (toggle) toggle.remove();
      document.dispatchEvent(new Event('turbo:load'));
    JS

    sleep 0.1
    errors = page.evaluate_script("window.__darkModeErrors || []")
    logs = console_logs
    messages = logs.map { |entry| entry.respond_to?(:message) ? entry.message : entry.to_s }

    assert errors.none? { |msg| msg.match?(/Cannot set (properties|property) of null|setting 'name'|dark-mode-toggle/i) },
           "Expected no dark mode errors after removing toggle, got: #{errors.join(" | ")}"

    assert messages.none? { |msg| msg.match?(/Cannot set (properties|property) of null|setting 'name'|dark-mode-toggle/i) },
           "Expected no dark mode errors in console logs, got: #{messages.join(" | ")}"
  end
end
