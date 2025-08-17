require "application_system_test_case"

class MediaApisSetupTest < ApplicationSystemTestCase
  test "mic and MediaSource are usable in headless Chrome" do
    visit new_user_session_path

    execute_script <<~JS
      (async () => {
        try {
          const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
          document.body.dataset.micOk = String(!!(stream && stream.active));
          // Clean up to avoid track leaks
          stream.getTracks().forEach(t => t.stop());
        } catch (e) {
          document.body.dataset.micErr = (e && e.name) ? e.name : String(e);
        }

        try {
          const ms = new MediaSource();
          document.body.dataset.msCtorOk = String(ms.readyState === 'closed');
          ms.addEventListener('sourceopen', () => {
            document.body.dataset.msOpened = "true";
          }, { once: true });

          const audio = document.createElement('audio');
          audio.muted = true; // ensure no playback restrictions and no sound in CI
          audio.src = URL.createObjectURL(ms);
          document.body.appendChild(audio);
          setTimeout(() => {
            // Nudge autoplay in some headless environments
            if (audio.play) audio.play().catch(() => {});
          }, 0);
        } catch (e) {
          document.body.dataset.msErr = (e && e.name) ? e.name : String(e);
        }
      })();
    JS

    # Wait for mic to be available
    assert page.has_selector?("body[data-mic-ok='true']", wait: 15), "getUserMedia failed: #{page.evaluate_script('document.body.dataset.micErr')}"
    # MediaSource constructible
    assert page.has_selector?("body[data-ms-ctor-ok='true']", wait: 5), "MediaSource not constructible: #{page.evaluate_script('document.body.dataset.msErr')}"
    # MediaSource 'sourceopen' fired after attaching to an <audio>
    assert page.has_selector?("body[data-ms-opened='true']", wait: 10), "MediaSource did not open: #{page.evaluate_script('document.body.dataset.msErr')}"
  end
end
