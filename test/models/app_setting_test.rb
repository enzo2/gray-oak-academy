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

  test "openai agent is enabled when model and shared OpenAI token are present" do
    openai = supported_apis(:openai)
    openai.update!(enabled: true, api_access_token: "sk-test")
    @app.update!(openai_agent_model: "gpt-5.2")

    assert_equal openai, @app.openai_agent_supported_api
    assert_equal "sk-test", @app.openai_agent_access_token
    assert @app.openai_agent_enabled?
    assert AppSetting.openai_agent_enabled?
  end

  test "openai agent uses selected openai provider when configured" do
    openai = supported_apis(:openai)
    openai.update!(enabled: true, api_access_token: "sk-openai")
    @app.update!(openai_agent_model: "gpt-5.2", openai_agent_supported_api_id: openai.id)

    assert_equal openai, @app.openai_agent_supported_api
    assert_equal "sk-openai", @app.openai_agent_access_token
    assert @app.openai_agent_enabled?
  end

  test "openai agent uses selected xai provider when configured" do
    openai = supported_apis(:openai)
    xai = supported_apis(:xai)
    openai.update!(enabled: true, api_access_token: "sk-openai")
    xai.update!(enabled: true, api_access_token: "sk-xai")
    @app.update!(openai_agent_model: "gpt-5.2", openai_agent_supported_api_id: xai.id)

    assert_equal xai, @app.openai_agent_supported_api
    assert_equal "sk-xai", @app.openai_agent_access_token
    assert @app.openai_agent_enabled?
  end

  test "openai agent falls back to openai when selected provider id is invalid" do
    openai = supported_apis(:openai)
    openai.update!(enabled: true, api_access_token: "sk-openai")
    @app.update!(openai_agent_model: "gpt-5.2", openai_agent_supported_api_id: "999999")

    assert_equal openai, @app.openai_agent_supported_api
    assert_equal "sk-openai", @app.openai_agent_access_token
  end

  test "openai agent falls back to openai when selected provider is not verified for agent runs" do
    openai = supported_apis(:openai)
    openai.update!(enabled: true, api_access_token: "sk-openai")
    @app.update!(openai_agent_model: "gpt-5.2", openai_agent_supported_api_id: supported_apis(:example_api).id)

    assert_equal openai, @app.openai_agent_supported_api
    assert_equal "sk-openai", @app.openai_agent_access_token
  end

  test "openai agent is disabled when model is blank" do
    supported_apis(:openai).update!(enabled: true, api_access_token: "sk-test")
    @app.update!(openai_agent_model: nil)

    assert_not @app.openai_agent_enabled?
  end

  test "openai_agent_supported_apis includes only responses-compatible selectable providers" do
    provider_ids = @app.openai_agent_supported_apis.pluck(:id)

    assert_includes provider_ids, supported_apis(:openai).id
    assert_includes provider_ids, supported_apis(:xai).id
    assert_not_includes provider_ids, supported_apis(:example_api).id
  end

  test "exa defaults are applied and key controls enabled state" do
    @app.update!(exa_research_model: nil, exa_api_key: nil)
    @app.reload

    assert_equal "exa-research", @app.exa_research_model
    assert_not @app.exa_enabled?

    @app.update!(exa_api_key: "exa-test-key")
    assert @app.exa_enabled?
    assert AppSetting.exa_enabled?
  end

  test "openai_agent_max_tool_turns uses seeded setting value" do
    assert_equal 20, @app.openai_agent_max_tool_turns
    assert_equal 20, AppSetting.openai_agent_max_tool_turns
  end

  test "openai_agent_max_tool_turns accepts positive values and returns nil when invalid" do
    @app.update!(openai_agent_max_tool_turns: "25")
    assert_equal 25, AppSetting.openai_agent_max_tool_turns

    @app.update!(openai_agent_max_tool_turns: "1000")
    assert_equal 50, AppSetting.openai_agent_max_tool_turns

    @app.update!(openai_agent_max_tool_turns: "0")
    assert_nil AppSetting.openai_agent_max_tool_turns

    @app.update!(openai_agent_max_tool_turns: "not-a-number")
    assert_nil AppSetting.openai_agent_max_tool_turns
  end
end
