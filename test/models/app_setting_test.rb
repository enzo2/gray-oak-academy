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

  test "speech providers include only openai and openrouter" do
    openrouter = SupportedApi.find_or_create_by!(api_base_uri: SupportedApi::OPENROUTER_BASE_URI) do |api|
      api.api_access_token = "openrouter-test-token"
      api.enabled = true
    end

    provider_ids = SupportedApi.speech_providers.pluck(:id)

    assert_includes provider_ids, supported_apis(:openai).id
    assert_includes provider_ids, openrouter.id
    assert_not_includes provider_ids, supported_apis(:xai).id
    assert_not_includes provider_ids, supported_apis(:example_api).id
  end

  test "fetch_openrouter_tts_models caches speech model ids" do
    cache = ActiveSupport::Cache::MemoryStore.new
    requested_urls = []
    response = {
      "data" => [
        { "id" => "x-ai/grok-voice-tts-1.0" },
        { "id" => "google/gemini-3.1-flash-tts-preview" },
        { "name" => "missing id" }
      ]
    }

    Rails.stub(:cache, cache) do
      HttpJsonService.stub(:get, ->(url) {
        requested_urls << url
        response
      }) do
        assert_equal(
          [ "google/gemini-3.1-flash-tts-preview", "x-ai/grok-voice-tts-1.0" ],
          AppSetting.fetch_openrouter_tts_models
        )
        assert_equal AppSetting.fetch_openrouter_tts_models, AppSetting.fetch_openrouter_tts_models
      end
    end

    assert_equal [ "#{SupportedApi::OPENROUTER_BASE_URI}models?output_modalities=speech" ], requested_urls
  end

  test "fetch_openrouter_image_model_data uses images models endpoint with token" do
    cache = ActiveSupport::Cache::MemoryStore.new
    openrouter = SupportedApi.find_or_create_by!(api_base_uri: SupportedApi::OPENROUTER_BASE_URI)
    openrouter.update!(api_access_token: "openrouter-test-token", enabled: true)
    calls = []
    response = {
      "data" => [
        {
          "id" => "openai/gpt-image-1",
          "architecture" => {
            "input_modalities" => [ "text", "image" ],
            "output_modalities" => [ "image" ]
          }
        }
      ]
    }

    Rails.stub(:cache, cache) do
      HttpJsonService.stub(:get, ->(url, headers: {}) {
        calls << { url: url, headers: headers }
        response
      }) do
        assert_equal response["data"], AppSetting.fetch_openrouter_image_model_data
        assert_equal response["data"], AppSetting.fetch_openrouter_image_model_data
      end
    end

    assert_equal 1, calls.length
    assert_equal "#{SupportedApi::OPENROUTER_BASE_URI}images/models", calls.first[:url]
    assert_equal "Bearer openrouter-test-token", calls.first[:headers]["Authorization"]
  end

  test "image_generation_configured? requires image input when two pass is enabled" do
    openrouter = SupportedApi.find_or_create_by!(api_base_uri: SupportedApi::OPENROUTER_BASE_URI)
    openrouter.update!(api_access_token: "openrouter-test-token", enabled: true)
    llm = Llm.create!(
      model: "openrouter/output-only-image",
      api_provider: SupportedApi::OPENROUTER_BASE_URI,
      supports_image_output: true,
      supports_image_input: false
    )

    @app.update!(image_llm_id: llm.id, image_generation_two_pass: true)
    refute AppSetting.image_generation_configured?

    @app.update!(image_generation_two_pass: false)
    assert AppSetting.image_generation_configured?
  end

  test "fetch_openrouter_tts_voices returns supported voices for selected model" do
    cache = ActiveSupport::Cache::MemoryStore.new
    response = {
      "data" => [
        {
          "id" => "x-ai/grok-voice-tts-1.0",
          "supported_voices" => [ "rex", "eve", "ara" ]
        },
        {
          "id" => "google/gemini-3.1-flash-tts-preview",
          "supported_voices" => [ "Puck" ]
        }
      ]
    }

    Rails.stub(:cache, cache) do
      HttpJsonService.stub(:get, response) do
        assert_equal [ "ara", "eve", "rex" ], AppSetting.fetch_openrouter_tts_voices(model: "x-ai/grok-voice-tts-1.0")
        assert_equal [], AppSetting.fetch_openrouter_tts_voices(model: "missing/model")
      end
    end
  end

  test "fetch_openrouter_stt_models caches transcription model ids" do
    cache = ActiveSupport::Cache::MemoryStore.new
    requested_urls = []
    response = {
      "data" => [
        { "id" => "mistralai/voxtral-mini-transcribe" },
        { "id" => "openai/whisper-1" }
      ]
    }

    Rails.stub(:cache, cache) do
      HttpJsonService.stub(:get, ->(url) {
        requested_urls << url
        response
      }) do
        assert_equal(
          [ "mistralai/voxtral-mini-transcribe", "openai/whisper-1" ],
          AppSetting.fetch_openrouter_stt_models
        )
        assert_equal AppSetting.fetch_openrouter_stt_models, AppSetting.fetch_openrouter_stt_models
      end
    end

    assert_equal [ "#{SupportedApi::OPENROUTER_BASE_URI}models?output_modalities=transcription" ], requested_urls
  end

  test "effective_token prefers token_override over provider token" do
    provider = supported_apis(:example_api)
    provider.update!(api_access_token: "provider-token")

    @app.update!(provider_supported_api_id: provider.id, token_override: "override-token")
    assert_equal "override-token", @app.effective_token

    @app.update!(token_override: nil)
    assert_equal "provider-token", @app.effective_token
  end

  test "blank token override is normalized to nil and falls back to provider token" do
    provider = supported_apis(:example_api)
    provider.update!(api_access_token: "provider-token")

    @app.update!(provider_supported_api_id: provider.id, token_override: "   ")

    assert_nil @app.reload.token_override
    assert_equal "provider-token", @app.effective_token
  end

  test "background agent is enabled when model and shared OpenAI token are present" do
    openai = supported_apis(:openai)
    openai.update!(enabled: true, api_access_token: "sk-test")
    @app.update!(background_agent_model: "gpt-5.2")

    assert_equal openai, @app.background_agent_supported_api
    assert_equal "sk-test", @app.background_agent_access_token
    assert @app.background_agent_enabled?
    assert AppSetting.background_agent_enabled?
  end

  test "background agent uses the selected provider and token when configured" do
    cases = [
      { provider: supported_apis(:openai), model: "gpt-5.2", token: "sk-openai" },
      { provider: supported_apis(:xai), model: "gpt-5.2", token: "sk-xai" },
      { provider: create_openrouter_supported_api(token: "sk-openrouter"), model: "anthropic/claude-sonnet-4.6", token: "sk-openrouter" }
    ]

    cases.each do |c|
      c[:provider].update!(enabled: true, api_access_token: c[:token])
      @app.update!(background_agent_model: c[:model], background_agent_supported_api_id: c[:provider].id)

      assert_equal c[:provider], @app.background_agent_supported_api, "provider #{c[:provider].api_base_uri}"
      assert_equal c[:token], @app.background_agent_access_token, "token for #{c[:provider].api_base_uri}"
      assert @app.background_agent_enabled?, "enabled for #{c[:provider].api_base_uri}"
    end
  end

  test "background agent reads and migrates legacy openai_agent settings" do
    openai = supported_apis(:openai)
    openai.update!(enabled: true, api_access_token: "sk-openai")
    legacy_settings = @app.settings.to_h.except(
      "background_agent_model",
      "background_agent_supported_api_id",
      "background_agent_max_tool_turns"
    ).merge(
      "openai_agent_model" => "gpt-5.2",
      "openai_agent_supported_api_id" => openai.id.to_s,
      "openai_agent_max_tool_turns" => "17"
    )
    @app.settings = legacy_settings
    @app.save!(validate: false)
    @app.reload

    assert_equal "gpt-5.2", @app.background_agent_model
    assert_equal openai, @app.background_agent_supported_api
    assert_equal 17, @app.background_agent_max_tool_turns

    assert @app.valid?
    assert_nil @app.settings["openai_agent_model"]
    assert_equal "gpt-5.2", @app.settings["background_agent_model"]

    @app.save!
    @app.reload
    assert_nil @app.settings["openai_agent_model"]
    assert_equal "gpt-5.2", @app.settings["background_agent_model"]
  end

  test "openrouter agent reports missing context metadata for manually entered model" do
    openrouter = create_openrouter_supported_api(token: "sk-openrouter")
    @app.update!(background_agent_model: "anthropic/manual-agent-model", background_agent_supported_api_id: openrouter.id)

    assert_nil @app.background_agent_context_length
    assert @app.background_agent_context_metadata_missing?
  end

  test "openrouter agent finds context metadata for selected model" do
    openrouter = create_openrouter_supported_api(token: "sk-openrouter")
    Llm.create!(
      model: "anthropic/metadata-agent-model",
      api_provider: SupportedApi::OPENROUTER_BASE_URI,
      context_length: 200_000
    )
    @app.update!(background_agent_model: "anthropic/metadata-agent-model", background_agent_supported_api_id: openrouter.id)

    assert_equal 200_000, @app.background_agent_context_length
    assert_not @app.background_agent_context_metadata_missing?
  end

  test "background agent falls back to openai when selected provider id is invalid" do
    openai = supported_apis(:openai)
    openai.update!(enabled: true, api_access_token: "sk-openai")
    @app.update!(background_agent_model: "gpt-5.2", background_agent_supported_api_id: "999999")

    assert_equal openai, @app.background_agent_supported_api
    assert_equal "sk-openai", @app.background_agent_access_token
  end

  test "background agent falls back to openai when selected provider is not verified for agent runs" do
    openai = supported_apis(:openai)
    openai.update!(enabled: true, api_access_token: "sk-openai")
    @app.update!(background_agent_model: "gpt-5.2", background_agent_supported_api_id: supported_apis(:example_api).id)

    assert_equal openai, @app.background_agent_supported_api
    assert_equal "sk-openai", @app.background_agent_access_token
  end

  test "background agent is disabled when model is blank" do
    supported_apis(:openai).update!(enabled: true, api_access_token: "sk-test")
    @app.update!(background_agent_model: nil)

    assert_not @app.background_agent_enabled?
  end

  test "background_agent_supported_apis includes only responses-compatible selectable providers" do
    openrouter = create_openrouter_supported_api
    provider_ids = @app.background_agent_supported_apis.pluck(:id)

    assert_includes provider_ids, supported_apis(:openai).id
    assert_includes provider_ids, openrouter.id
    assert_includes provider_ids, supported_apis(:xai).id
    assert_not_includes provider_ids, supported_apis(:example_api).id
  end

  test "per-teacher Codex preference defaults off and requires a model when enabled" do
    assert_not @app.background_agent_prefer_user_codex?

    @app.background_agent_prefer_user_codex = "1"
    @app.background_agent_codex_model = nil

    assert_not @app.valid?
    assert_includes @app.errors[:background_agent_codex_model], "must be set when per-teacher Codex is enabled"
  end

  test "background agent availability uses only a teacher's own OAuth credentials" do
    supported_apis(:openai).update!(api_access_token: nil)
    teacher = users(:admin)
    student = users(:student)
    teacher.setting.openai_oauth_access_token = "teacher-codex-token"
    teacher.setting.openai_oauth_expires_at = 1.hour.from_now.iso8601
    teacher.setting.save!(validate: false)
    @app.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )

    assert @app.background_agent_enabled_for?(teacher)
    assert AppSetting.background_agent_enabled_for?(teacher)
    assert_not @app.background_agent_enabled_for?(student)
    assert_not AppSetting.background_agent_enabled_for?(student)
    assert_not AppSetting.background_agent_enabled_for?(users(:admin2))
  end

  test "expired access-only OAuth credentials do not enable background agents" do
    supported_apis(:openai).update!(api_access_token: nil)
    teacher = users(:admin)
    teacher.setting.openai_oauth_access_token = "expired-codex-token"
    teacher.setting.openai_oauth_refresh_token = nil
    teacher.setting.openai_oauth_expires_at = 1.hour.ago.iso8601
    teacher.setting.save!(validate: false)
    @app.update!(
      background_agent_prefer_user_codex: "1",
      background_agent_codex_model: "gpt-5.4-codex"
    )

    assert_not @app.background_agent_enabled_for?(teacher)
    assert_not AppSetting.background_agent_enabled_for?(teacher)

    teacher.setting.openai_oauth_refresh_token = "refresh-token"
    teacher.setting.save!(validate: false)

    assert @app.background_agent_enabled_for?(teacher)
    assert AppSetting.background_agent_enabled_for?(teacher)
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

  test "outline research stub toggle is development-only" do
    @app.update!(course_outline_research_stub_enabled: "1")

    Rails.env.stub(:development?, true) do
      assert @app.course_outline_research_stub_enabled?
      assert AppSetting.course_outline_research_stub_enabled?
    end

    Rails.env.stub(:development?, false) do
      assert_not @app.course_outline_research_stub_enabled?
      assert_not AppSetting.course_outline_research_stub_enabled?
    end
  end

  test "background_agent_max_tool_turns uses seeded setting value" do
    assert_equal 20, @app.background_agent_max_tool_turns
    assert_equal 20, AppSetting.background_agent_max_tool_turns
  end

  test "background_agent_max_tool_turns accepts positive values and returns nil when invalid" do
    @app.update!(background_agent_max_tool_turns: "25")
    assert_equal 25, AppSetting.background_agent_max_tool_turns

    @app.update!(background_agent_max_tool_turns: "1000")
    assert_equal 50, AppSetting.background_agent_max_tool_turns

    @app.update!(background_agent_max_tool_turns: "0")
    assert_nil AppSetting.background_agent_max_tool_turns

    @app.update!(background_agent_max_tool_turns: "not-a-number")
    assert_nil AppSetting.background_agent_max_tool_turns
  end

  test "embedding model validation is skipped when embedding_model is unchanged" do
    create_openrouter_supported_api

    AppSetting.stub(:fetch_openrouter_embedding_models, [ "openai/text-embedding-3-small" ]) do
      @app.update!(embedding_model: "openai/text-embedding-3-small")
    end

    AppSetting.stub(:fetch_openrouter_embedding_models, -> { flunk("expected embedding model validation to be skipped") }) do
      assert @app.update(exa_research_model: "exa-research-pro")
    end
  end

  test "embedding model validation runs when embedding_model changes" do
    create_openrouter_supported_api

    AppSetting.stub(:fetch_openrouter_embedding_models, []) do
      assert_not @app.update(embedding_model: "invalid-embedding-model")
    end

    assert_includes @app.errors[:embedding_model], "must be a valid OpenRouter embedding model"
  end

  private

  def create_openrouter_supported_api(token: "openrouter-test-token")
    SupportedApi.create!(
      api_base_uri: SupportedApi::OPENROUTER_BASE_URI,
      api_access_token: token,
      enabled: true
    )
  end
end
