require "test_helper"

class MessagesTtsStreamTest < ActionDispatch::IntegrationTest
  def setup
    @message = messages(:student_message_assistant)
    @conversation = @message.conversation
    @user = @conversation.user
    sign_in @user
  end

  test "GET /messages/:id/tts_stream returns not_implemented when speech is not configured" do
    AppSetting.stub(:speech_configured?, false) do
      get tts_stream_message_path(@message)
      assert_response :not_implemented
    end
  end

  test "GET /messages/:id/tts_stream returns audio/webm when TTS configured" do
    # Ensure AppSetting is configured for speech TTS using fixture supported api
    app = AppSetting.first
    app.update!(
      stt_method: "speech",
      provider_supported_api_id: supported_apis(:example_api).id,
      tts_model: "tts-1",
      tts_voice: "alloy"
    )
    assert AppSetting.tts_configured?, "TTS must be configured for this test"

    with_faraday_tts_stub(fixture: "test/fixtures/files/sample.ogg") do
      get tts_stream_message_path(@message)
      assert_response :success
      assert_equal "audio/webm", response.media_type
      assert_operator response.body.bytesize, :>, 0
    end
  end
end
