require "application_system_test_case"
require "timeout"

class TurboStreamEventsTest < ApplicationSystemTestCase
  def setup
    @student = users(:student)
    sign_in @student
    @conversation = conversations(:student_generic_conversation)
  end

  test "turbo stream lifecycle events are emitted with the stream source element" do
    visit conversation_path(@conversation)

    page.execute_script(<<~JS)
      window.__streamEvents = [];

      document.addEventListener("turbo:stream-connected", (event) => {
        window.__streamEvents.push({
          type: "connected",
          hasConnectedAttribute: event.detail?.source?.hasAttribute("connected"),
          signedStreamName: event.detail?.source?.getAttribute("signed-stream-name")
        });
      });

      document.addEventListener("turbo:stream-disconnected", (event) => {
        window.__streamEvents.push({
          type: "disconnected",
          signedStreamName: event.detail?.source?.getAttribute("signed-stream-name")
        });
      });

      const source = document.querySelector("turbo-cable-stream-source");
      if (source && source.parentElement) {
        const parent = source.parentElement;
        const nextSibling = source.nextSibling;
        parent.removeChild(source);
        setTimeout(() => {
          if (nextSibling) {
            parent.insertBefore(source, nextSibling);
          } else {
            parent.appendChild(source);
          }
        }, 0);
      }
    JS

    assert_eventually do
      page.evaluate_script("window.__streamEvents.some(event => event.type === 'disconnected')")
    end

    assert_eventually do
      page.evaluate_script("window.__streamEvents.some(event => event.type === 'connected')")
    end

    has_connected_attr = page.evaluate_script(<<~JS)
      (window.__streamEvents || []).find(event => event.type === "connected")?.hasConnectedAttribute
    JS
    assert_equal true, has_connected_attr
  end

  test "connection indicator marks connected after page load" do
    visit conversation_path(@conversation)

    assert_eventually do
      page.has_css?("[data-connection-status-target='indicator'].text-success-600")
    end

    tooltip_content = page.find("[data-connection-status-target='tooltip']")["data-tooltip-content"]
    assert_equal "Connected", tooltip_content
  end

  test "connection indicator flips to disconnected when stream drops" do
    visit conversation_path(@conversation)

    assert_eventually do
      page.has_css?("[data-connection-status-target='indicator'].text-success-600")
    end

    page.execute_script(<<~JS)
      const source = document.querySelector("turbo-cable-stream-source");
      if (source) {
        source.removeAttribute("connected");
      }
    JS

    assert_eventually do
      page.has_css?("[data-connection-status-target='indicator'].text-red-600")
    end

    tooltip_content = page.find("[data-connection-status-target='tooltip']")["data-tooltip-content"]
    assert_equal "Disconnected", tooltip_content
  end

  private

  def assert_eventually(timeout: Capybara.default_max_wait_time)
    Timeout.timeout(timeout) do
      loop do
        break if yield

        sleep 0.1
      end
    end
  end
end
