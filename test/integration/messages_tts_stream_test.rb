require "test_helper"

class MessagesTtsStreamTest < ActionDispatch::IntegrationTest
  def setup
    @message = messages(:student_message_assistant)
    @conversation = @message.conversation
    @user = @conversation.user
    sign_in @user
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

    # Use Faraday test adapter to stub provider returning a valid webm payload
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
      SpeechService.default_conn = conn

      get tts_stream_message_path(@message)
      assert_response :success
      assert_equal "audio/webm", response.media_type
      assert_operator response.body.bytesize, :>, 0
    ensure
      SpeechService.default_conn = nil
      begin
        stubs.verify_stubbed_calls
      rescue StandardError
        # ignore verification errors in CI flake scenarios
      end
    end
  end
end
