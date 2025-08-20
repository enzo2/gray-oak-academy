require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
  def setup
    @app = AppSetting.first
  end

  test "tts_configured? is true when provider and token exist" do
    @app.update!(
      provider_supported_api_id: supported_apis(:example_api).id,
      token_override: nil,
      tts_model: "tts-1",
      tts_voice: "alloy"
    )

    assert AppSetting.speech_configured?
    assert AppSetting.tts_configured?
  end

  test "stt_configured? returns true for speech method when provider, token, and model present" do
    @app.update!(
      stt_method: "speech",
      stt_model: "transcribe-1",
      provider_supported_api_id: supported_apis(:example_api).id,
      token_override: nil
    )

    assert AppSetting.stt_configured?
  end

  test "stt_configured? returns true for chat method when stt_model_id present" do
    llm = llms(:one) rescue Llm.create!(model: "test-model", api_provider: "https://example.com/")
    @app.update!(stt_method: "chat", stt_model_id: llm.id)
    assert AppSetting.stt_configured?
  end

  test "effective_token prefers token_override over provider token" do
    provider = supported_apis(:example_api)
    provider.update!(api_access_token: "provider-token")

    @app.update!(provider_supported_api_id: provider.id, token_override: "override-token")
    assert_equal "override-token", @app.effective_token

    @app.update!(token_override: nil)
    assert_equal "provider-token", @app.effective_token
  end
end
