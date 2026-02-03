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
      # Rely on the help text rather than the icon name to avoid timing races in CI
      assert_text "Recording", wait: 10

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
      assert_selector "#recordButton", wait: 5
      find("#recordButton").click
      # Simulate recording for a short period
      # Rely on the help text rather than the icon name to avoid timing races in CI
      assert_text "Recording", wait: 10

      # Click stop to send the message
      find("#recordButton").click
      assert_selector "#recordButton", wait: 5
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
        assert_selector '#recordButton[name="mic"]', wait: 5
        find("#recordButton").click
        # Simulate recording for a short period
        # Rely on the help text rather than the icon name to avoid unidentifiable issue in CI
        assert_text "Recording", wait: 5

        # Click stop to send the message
        find("#recordButton").click
        assert_selector '#recordButton[name="mic"]'
        assert_no_text "Recording"
        assert_text "Transcribing...", wait: 5

        wait_for_enqueued_job(GetLlmCompletionJob)
        perform_enqueued_jobs(only: GetLlmCompletionJob)

        wait_for_enqueued_job(TranscribeAudioJob)
        perform_enqueued_jobs(only: TranscribeAudioJob)

        # Wait for the "Transcribing..." message to disappear, indicating the update has been broadcast
        assert_no_text "Transcribing...", wait: 5

        # Wait for the transcribed message to appear
        assert_selector ".message-content", text: "This is a test transcription from conversation LLM.", wait: 5
      end
    end
  end

  private

  def wait_for_enqueued_job(job_class, timeout: 5)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    loop do
      return if enqueued_jobs.any? { |job| job[:job] == job_class }
      if (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) > timeout
        flunk "Timed out waiting for #{job_class} to be enqueued"
      end
      sleep 0.05
    end
  end

  test "TTS playback works" do
    AppSetting.first.update!(
      stt_method: "speech", stt_model: "stt-model", tts_model: "tts-1", tts_voice: "alloy",
      provider_supported_api_id: SupportedApi.find_by(api_base_uri: "https://api.example.com/").id
    )
    assert AppSetting.tts_configured?

    visit conversation_path(@conversation)

    # Simulate LLM sending an assistant message
    message = Message.create!(conversation: @conversation, role: :assistant, content: "Hello, this is a test message for TTS.")
    perform_enqueued_jobs # Ensure the message is broadcast and rendered
    assert_selector "#message_#{message.id}_buttons", wait: 5

    with_faraday_tts_stub(fixture: "test/fixtures/files/sample.ogg") do
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
      assert_selector "#message_#{message.id}_buttons sl-icon-button[name='stop-circle']", wait: 10
      # Assert button state eventually changes back to idle (volume-up) when playback ends
      assert_selector "#message_#{message.id}_buttons sl-icon-button[name='volume-up']", wait: 10
    end
  end
end
