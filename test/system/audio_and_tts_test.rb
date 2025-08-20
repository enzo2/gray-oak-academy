require "application_system_test_case"

class AudioAndTtsTest < ApplicationSystemTestCase
  def setup
    @student = users(:student)
    sign_in @student
    @conversation = conversations(:student_generic_conversation)
  end

  test "recording and submitting for transcription works" do
    AppSetting.first.update!(
      stt_method: "speech", stt_model: "stt-model", tts_model: "tts-1", tts_voice: "alloy",
      provider_supported_api_id: SupportedApi.find_by(api_base_uri: "https://api.example.com/").id
    )
    # Make sure the conversation will use transcription endpoint (not raw audio upload) in this test.
    # Some fixtures default LLMs to support audio input; force-disable audio input for this test run.
    llm = @conversation.llm_in_use
    llm&.update!(supports_audio_input: false)
    assert AppSetting.stt_configured?

    visit conversation_path(@conversation)

    # Stub SpeechService to return transcription
    stub_speech_service(transcription: "This is a test transcription.") do
      # Click the record button
      assert_selector '#recordButton[name="mic"]', wait: 3
      find("#recordButton").click
      # Simulate recording for a short period
      sleep 0.2
      assert_selector '#recordButton[name="stop-circle"]', wait: 5
      assert_text "Recording"

      # Click stop to send the message
      find("#recordButton").click
      assert_selector '#recordButton[name="mic"]'
      assert_no_text "Recording"

      # Wait for the transcribed message to appear
      assert_selector ".message-content", text: "This is a test transcription.", wait: 2
    end
  end

  test "recording and submitting for transcription works with chat STT and no Speech API" do
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
    llm = @conversation.llm_in_use
    llm&.update!(supports_audio_input: false)

    assert AppSetting.stt_configured?
    refute AppSetting.speech_configured?

    visit conversation_path(@conversation)

    # Stub SpeechService to return transcription
    stub_speech_service(transcription: "Chat STT transcription.") do
      # Click the record button
      assert_selector '#recordButton[name="mic"]', wait: 3
      find("#recordButton").click
      # Simulate recording for a short period
      assert_selector '#recordButton[name="stop-circle"]', wait: 3
      assert_text "Recording"

      # Click stop to send the message
      find("#recordButton").click
      assert_selector '#recordButton[name="mic"]'
      assert_no_text "Recording"

      # Wait for the transcribed message to appear
      assert_selector ".message-content", text: "Chat STT transcription.", wait: 5
    end
  end

  test "recording and submitting raw audio message completion works without STT configured" do
    # Ensure STT is NOT configured
    AppSetting.first.update!(
      stt_method: "speech",
      stt_model: nil,
      provider_supported_api_id: nil,
      token_override: nil,
      tts_model: nil,
      tts_voice: nil
    )
    refute AppSetting.stt_configured?

    # But ensure the conversation's LLM supports audio input
    llm = @conversation.llm_in_use
    llm&.update!(supports_audio_input: true)
    assert @conversation.audio_input_permitted?

    visit conversation_path(@conversation)

    # Stub OpenaiApiService to avoid external network calls and Stub SpeechService to return transcription
    OpenaiApiService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        # complete should be a no-op for streaming tests here (GetLlmCompletionJob will not raise)
        def o.complete(*_args); ""; end
      end
    }) do
        stub_speech_service(transcription: "This is a test transcription from conversation LLM.") do
        # Click the record button
        assert_selector '#recordButton[name="mic"]', wait: 3
        find("#recordButton").click
        # Simulate recording for a short period
        assert_selector '#recordButton[name="stop-circle"]', wait: 3
        assert_text "Recording"

        # Click stop to send the message
        find("#recordButton").click
        assert_selector '#recordButton[name="mic"]'
        assert_no_text "Recording"
        sleep 0.2
        perform_enqueued_jobs # GetLlmCompletionJob runs...
        sleep 0.5
        perform_enqueued_jobs # then TranscribeAudioJob

        # Wait for the "Transcribing..." message to disappear, indicating the update has been broadcast
        assert_no_text "Transcribing...", wait: 5

        # Wait for the transcribed message to appear
        assert_selector ".message-content", text: "This is a test transcription from conversation LLM.", wait: 5
      end
    end
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
    assert_selector "#message_#{message.id}_buttons", wait: 5

    with_faraday_tts_stub(fixture: "test/fixtures/files/sample.webm") do
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
      sleep 1 # Allow time for the click event to be processed (fails on CI but not locally)

      # Assert button state changes to playing (when Audio 'playing' fires)
      assert_selector "#message_#{message.id}_buttons sl-icon-button[name='stop-circle']", wait: 5

      # Assert button state eventually changes back to idle (volume-up) when playback ends
      assert_selector "#message_#{message.id}_buttons sl-icon-button[name='volume-up']", wait: 10
    end
  end
end
