require "application_system_test_case"

class AudioAndTtsTest < ApplicationSystemTestCase
  def setup
    @student = users(:student)
    sign_in @student
    @conversation = conversations(:student_generic_conversation)
  end

  test "audio recording and transcription works" do
    AppSetting.first.update!(
      stt_method: "speech",
      stt_model: "stt-model",
      provider_supported_api_id: SupportedApi.find_by(api_base_uri: "https://api.example.com/").id
    )

    visit conversation_path(@conversation)

    # Stub SpeechService to return transcription
    SpeechService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        def o.transcribe(_file); "This is a test transcription."; end
        def o.sanitize_tts_text(text); text; end
      end
    }) do
      # Click the record button
      find("#recordButton").click
      assert_selector '#recordButton[name="stop-circle"]'
      assert_text "Recording...press stop to send message."

      # Simulate recording for a short period
      sleep 1

      # Click stop to send the message
      find("#recordButton").click
      assert_selector '#recordButton[name="mic"]'
      assert_no_text "Recording...press stop to send message."

      # Wait for the transcribed message to appear
      assert_selector ".message-content", text: "This is a test transcription.", wait: 10
    end
  end

  test "TTS playback works" do
    AppSetting.first.update!(
      tts_model: "tts-1",
      tts_voice: "alloy",
      provider_supported_api_id: SupportedApi.find_by(api_base_uri: "https://api.example.com/").id
    )

    visit conversation_path(@conversation)

    # Simulate LLM sending an assistant message
    message = Message.create!(conversation: @conversation, role: :assistant, content: "Hello, this is a test message for TTS.")
    message.broadcast_created

    # Stub SpeechService to simulate streaming audio
    SpeechService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        def o.tts_stream(_text)
          yield "chunk1"
          yield "chunk2"
        end
        def o.sanitize_tts_text(text); text; end
      end
    }) do
      # Wait for the TTS button to appear and be enabled
      tts_button_selector = "#message_#{message.id}_buttons sl-icon-button[name='volume-up']"
      assert_selector tts_button_selector, visible: true, wait: 10
      find(tts_button_selector).click

      # Assert button state changes to playing
      assert_selector "#message_#{message.id}_buttons sl-icon-button[name='stop-circle']", wait: 5

      # Simulate audio playback ending
      # In a real browser, this would happen automatically. Here we can't directly control it.
      # We'll rely on the stubbed `tts_stream` yielding chunks and the button state changing back.
      # For a more robust test, one might need to mock the Audio object itself.
      sleep 2 # Give some time for the "chunks" to be "streamed"

      # Assert button state changes back to idle (volume-up)
      assert_selector "#message_#{message.id}_buttons sl-icon-button[name='volume-up']", wait: 5
    end
  end
end
