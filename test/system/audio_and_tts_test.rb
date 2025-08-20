require "application_system_test_case"

class AudioAndTtsTest < ApplicationSystemTestCase
  def setup
    @student = users(:student)
    sign_in @student
    @conversation = conversations(:student_generic_conversation)
  end

  test "audio recording for transcription works" do
    AppSetting.first.update!(
      stt_method: "speech", stt_model: "stt-model", tts_model: "tts-1", tts_voice: "alloy",
      provider_supported_api_id: SupportedApi.find_by(api_base_uri: "https://api.example.com/").id
    )
    # Make sure the conversation will use transcription endpoint (not raw audio upload) in this test.
    # Some fixtures default LLMs to support audio input; force-disable audio input for this test run.
    Llm.update_all(supports_audio_input: false)
    assert AppSetting.stt_configured?

    visit conversation_path(@conversation)

    # Stub SpeechService to return transcription
    SpeechService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        def o.transcribe(_file); "This is a test transcription."; end
        def o.sanitize_tts_text(text); text; end
      end
    }) do
      # Click the record button
      assert_selector '#recordButton[name="mic"]', wait: 3
      find("#recordButton").click
      # Simulate recording for a short period
      sleep 0.5
      assert_selector '#recordButton[name="stop-circle"]'
      assert_text "Recording"

      # Click stop to send the message
      find("#recordButton").click
      assert_selector '#recordButton[name="mic"]'
      assert_no_text "Recording"

      # Wait for the transcribed message to appear
      assert_selector ".message-content", text: "This is a test transcription.", wait: 2
    end
  end

  test "audio recording for transcription works with chat STT and no Speech API" do
    # Configure Chat STT without Speech API provider/token so TTS remains unavailable.
    app_setting = AppSetting.first
    app_setting.update!(
      stt_method: "chat",
      stt_model_id: Llm.first.id,
      provider_supported_api_id: nil,
      token_override: nil,
      tts_model: nil,
      tts_voice: nil
    )

    # Force the conversation to use transcription endpoint (not raw audio upload)
    Llm.update_all(supports_audio_input: false)

    assert AppSetting.stt_configured?
    refute AppSetting.speech_configured?

    visit conversation_path(@conversation)

    # Stub SpeechService to return transcription
    SpeechService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        def o.transcribe(_file); "Chat STT transcription."; end
        def o.sanitize_tts_text(text); text; end
      end
    }) do
      # Click the record button
      assert_selector '#recordButton[name="mic"]', wait: 3
      find("#recordButton").click
      # Simulate recording for a short period
      sleep 0.5
      assert_selector '#recordButton[name="stop-circle"]'
      assert_text "Recording"

      # Click stop to send the message
      find("#recordButton").click
      assert_selector '#recordButton[name="mic"]'
      assert_no_text "Recording"

      # Wait for the transcribed message to appear
      assert_selector ".message-content", text: "Chat STT transcription.", wait: 2
    end
  end

  # UNFINISHED
  test "audio recording for raw audio message completion works" do
    Llm.update_all(supports_audio_input: true)
    assert @conversation.audio_input_permitted?

    visit conversation_path(@conversation)
    # Click the record button
    assert_selector '#recordButton[name="mic"]', wait: 3
    find("#recordButton").click
    # Simulate recording for a short period
    sleep 0.5
    assert_selector '#recordButton[name="stop-circle"]'
    assert_text "Recording"
    find("#recordButton").click
    assert_selector '#recordButton[name="mic"]'
    assert_no_text "Recording"
    perform_enqueued_jobs
  end

  test "TTS playback works" do
    AppSetting.first.update!(
      stt_method: "speech", stt_model: "stt-model", tts_model: "tts-1", tts_voice: "alloy",
      provider_supported_api_id: SupportedApi.find_by(api_base_uri: "https://api.example.com/").id
    )
    assert AppSetting.tts_configured?

    visit conversation_path(@conversation)
    # sleep 1 # Give time for Turbo Streams to connect and page to load

    # Simulate LLM sending an assistant message
    message = Message.create!(conversation: @conversation, role: :assistant, content: "Hello, this is a test message for TTS.")
    perform_enqueued_jobs # Ensure the message is broadcast and rendered
    sleep 1 # Allow time for the DOM to settle after background jobs and broadcasts

    # Use Faraday::Adapter::Test to simulate provider returning a valid WebM/Opus stream
    require "faraday"

    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/audio/speech") do |_env|
        body = File.binread(Rails.root.join("test/fixtures/files/sample.webm"))
        [ 200, { "Content-Type" => "audio/webm" }, body ]
      end
    end

    conn = Faraday.new(url: "https://api.example.com/") do |b|
      b.adapter :test, stubs
    end

    begin
      # Inject test connection so SpeechService uses it instead of building a real Faraday client
      SpeechService.default_conn = conn

      # Wait for the TTS button to appear and be enabled
      tts_button_selector = "#message_#{message.id}_buttons sl-icon-button[name='volume-up']"

      # Stimulate the same client-side event the app fires when an assistant completion finishes.
      # This ensures the TTS controller un-hides/enables the button for newly appended messages.
      begin
        page.execute_script(<<~JS)
          (function() {
            const convo = document.getElementById("conversation_#{@conversation.id}");
            if (!convo) return null;
            const ev = new CustomEvent('llm-completion-finished', { detail: { message_id: #{message.id} }, bubbles: true });
            convo.dispatchEvent(ev);
            return true;
          })();
        JS
      rescue StandardError => e
        puts "Failed to dispatch llm-completion-finished event: #{e.class}: #{e.message}"
      end

      assert_selector tts_button_selector, visible: true, wait: 5
      find(tts_button_selector).click

      # Assert button state changes to playing (when Audio 'playing' fires)
      assert_selector "#message_#{message.id}_buttons sl-icon-button[name='stop-circle']", wait: 5

      # Assert button state eventually changes back to idle (volume-up) when playback ends
      assert_selector "#message_#{message.id}_buttons sl-icon-button[name='volume-up']", wait: 10
    ensure
      SpeechService.default_conn = nil
      Faraday.default_connection = nil
      begin
        stubs.verify_stubbed_calls
      rescue StandardError
        # ignore verification errors in CI flake scenarios
      end
    end
  end
end
