require "application_system_test_case"

class FlashToastTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test "flash.now from turbo stream update renders custom toast" do
    applet = Applet.create!(title: "Toast test applet", code: "console.log('toast')", user: @admin)

    visit applets_path
    assert_selector "#flash_bar", visible: :all
    assert_selector "#applet_#{applet.id}"

    within "#applet_#{applet.id}" do
      page.accept_confirm do
        find("a[data-turbo-method='delete']").click
      end
    end

    assert_no_selector "#applet_#{applet.id}", wait: 5
    assert_selector ".toast-item", text: "Applet deleted!", wait: 5
    assert_no_selector "sl-alert", wait: 1
  end

  test "turbo stream append to flash_bar renders custom toast" do
    visit applets_path
    assert_selector "#flash_bar", visible: :all

    append_broadcast_toast("Broadcast warning toast", type: "warning")

    assert_selector ".toast-item", text: "Broadcast warning toast", wait: 5
  end

  test "a toast survives a turbo refresh that lands right after it appears" do
    # A background job's broadcast_refresh can morph the page moments after it
    # appended an error toast (e.g. an instant Codex 429). The permanent toast rack
    # must keep the toast instead of being torn down and dismissing it prematurely.
    visit applets_path
    assert_selector "#toast-rack[data-turbo-permanent]", visible: :all

    append_broadcast_toast("Persisted error toast", type: "error")
    assert_selector ".toast-item", text: "Persisted error toast", wait: 5

    rendered = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      document.addEventListener("turbo:render", () => done(true), { once: true });
      const refresh = document.createElement("turbo-stream");
      refresh.setAttribute("action", "refresh");
      document.body.appendChild(refresh);
      setTimeout(() => done(false), 4000);
    JS

    assert rendered, "expected the turbo refresh to render the page"
    assert_selector ".toast-item", text: "Persisted error toast"
  end

  private

  def append_broadcast_toast(message, type:)
    page.execute_script(<<~JS)
      const stream = document.createElement("turbo-stream");
      stream.setAttribute("action", "append");
      stream.setAttribute("target", "flash_bar");
      stream.innerHTML = `
        <template>
          <div
            class="hidden"
            data-flash-toast-bridge-target="message"
            data-toast-type="#{type}"
            data-html-safe="false"
            data-turbo-temporary>
            #{message}
          </div>
        </template>
      `;
      document.body.appendChild(stream);
    JS
  end
end
