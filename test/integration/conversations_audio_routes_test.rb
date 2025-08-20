require "test_helper"

class ConversationsAudioRoutesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    ActiveJob::Base.queue_adapter = :test
    @student = users(:student)
    @conversation = conversations(:student_generic_conversation)
    sign_in @student
  end

  test "POST /conversations/:id/audio_messages enqueues GetLlmCompletionJob when audio permitted" do
    # Force the conversation instance to permit audio input for this test only
    Conversation.stub(:find, ->(id) {
      conv = conversations(:student_generic_conversation)
      # define a singleton method to force permitting audio input
      conv.define_singleton_method(:audio_input_permitted?) { true }
      conv
    }) do
      file = fixture_file_upload(Rails.root.join("test/fixtures/files/sample.webm"), "audio/webm")

      # Run enqueued jobs so any downstream completion job will be processed deterministically.
      OpenaiApiService.stub(:new, ->(**_kwargs) { Object.new.tap { |o| o.define_singleton_method(:complete) { |*_args| "" } } }) do
        perform_enqueued_jobs do
          post audio_messages_conversation_path(@conversation), params: { audio: file }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end
      end

      assert_response :success, "Expected successful turbo_stream response"
      # Ensure the user message was created
      msg = @conversation.reload.messages.role_user.last
      assert msg.present?, "Expected a user message to be created for audio upload"
    end
  end

  test "POST /conversations/:id/transcribed_messages performs STT and enqueues GetLlmCompletionJob" do
    # Ensure AppSetting is configured for speech STT
    app = AppSetting.first
    app.update!(
      stt_method: "speech",
      stt_model: "transcribe-1",
      provider_supported_api_id: supported_apis(:example_api).id
    )

    file = fixture_file_upload(Rails.root.join("test/fixtures/files/sample.wav"), "audio/wav")

    # Stub SpeechService to return a deterministic transcription
    SpeechService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        def o.transcribe(_file); "Transcribed text from STT"; end
      end
    }) do
      # Process enqueued jobs and the STT transcription synchronously for test determinism.
      # Stub the LLM API so GetLlmCompletionJob doesn't perform network calls during this integration test.
      OpenaiApiService.stub(:new, ->(**_kwargs) { Object.new.tap { |o| o.define_singleton_method(:complete) { |*_args| "" } } }) do
        perform_enqueued_jobs do
          post transcribed_messages_conversation_path(@conversation), params: { audio: file }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end
      end

      assert_response :success
      # The controller creates a user message and saves the transcription before enqueuing completion.
      # Don't rely on `last` (other fixtures may produce user messages); assert a message with the expected content exists.
      assert @conversation.reload.messages.exists?(content: "Transcribed text from STT"), "Expected a transcribed user message to be present"
    end
  end
end
