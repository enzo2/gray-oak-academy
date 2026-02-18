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

    page.execute_script(<<~JS)
      const stream = document.createElement("turbo-stream");
      stream.setAttribute("action", "append");
      stream.setAttribute("target", "flash_bar");
      stream.innerHTML = `
        <template>
          <div
            class="hidden"
            data-flash-toast-bridge-target="message"
            data-toast-type="warning"
            data-html-safe="false"
            data-turbo-temporary>
            Broadcast warning toast
          </div>
        </template>
      `;
      document.body.appendChild(stream);
    JS

    assert_selector ".toast-item", text: "Broadcast warning toast", wait: 5
  end
end
