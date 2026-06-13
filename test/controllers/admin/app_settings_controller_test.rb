require "test_helper"

class Admin::AppSettingsControllerTest < ActionDispatch::IntegrationTest
  test "superuser keeps exa api key when masked value is submitted" do
    app_setting = AppSetting.first
    app_setting.update!(exa_api_key: "exa-test-key")

    sign_in users(:super_user)

    patch admin_app_setting_path, params: {
      app_setting: {
        exa_api_key: AppSetting::MASKED_SECRET_VALUE,
        exa_research_model: "exa-research"
      }
    }

    assert_redirected_to edit_admin_app_setting_path
    assert_equal "exa-test-key", app_setting.reload.exa_api_key
  end

  test "superuser can clear exa api key by submitting blank value" do
    app_setting = AppSetting.first
    app_setting.update!(exa_api_key: "exa-test-key")

    sign_in users(:super_user)

    patch admin_app_setting_path, params: {
      app_setting: {
        exa_api_key: "",
        exa_research_model: "exa-research"
      }
    }

    assert_redirected_to edit_admin_app_setting_path
    assert app_setting.reload.exa_api_key.blank?
  end

  test "superuser keeps token override when masked value is submitted" do
    app_setting = AppSetting.first
    app_setting.update!(token_override: "speech-override")

    sign_in users(:super_user)

    patch admin_app_setting_path, params: {
      app_setting: {
        token_override: AppSetting::MASKED_SECRET_VALUE
      }
    }

    assert_redirected_to edit_admin_app_setting_path
    assert_equal "speech-override", app_setting.reload.token_override
  end

  test "superuser can clear token override by submitting blank value" do
    app_setting = AppSetting.first
    app_setting.update!(token_override: "speech-override")

    sign_in users(:super_user)

    patch admin_app_setting_path, params: {
      app_setting: {
        token_override: ""
      }
    }

    assert_redirected_to edit_admin_app_setting_path
    assert_nil app_setting.reload.token_override
  end

  test "superuser can set background agent provider id" do
    app_setting = AppSetting.first
    sign_in users(:super_user)

    patch admin_app_setting_path, params: {
      app_setting: {
        openai_agent_supported_api_id: supported_apis(:xai).id,
        openai_agent_model: "gpt-5.2"
      }
    }

    assert_redirected_to edit_admin_app_setting_path
    assert_equal supported_apis(:xai).id.to_s, app_setting.reload.openai_agent_supported_api_id.to_s
  end

  test "superuser can fetch llm models for selected provider" do
    sign_in users(:super_user)
    Llm.create!(model: "xai-model-alpha", api_provider: supported_apis(:xai).api_base_uri)
    Llm.create!(model: "openai-model-beta", api_provider: supported_apis(:openai).api_base_uri)

    get llm_models_admin_app_setting_path(format: :turbo_stream), params: { api_uri: supported_apis(:xai).api_base_uri }

    assert_response :success
    assert_includes response.body, "xai-model-alpha"
    assert_not_includes response.body, "openai-model-beta"
  end

  test "speech provider select includes only openai and openrouter" do
    openrouter = SupportedApi.find_or_create_by!(api_base_uri: SupportedApi::OPENROUTER_BASE_URI) do |api|
      api.api_access_token = "openrouter-test-token"
      api.enabled = true
    end
    sign_in users(:super_user)

    AppSetting.stub(:fetch_openrouter_embedding_models, []) do
      get edit_admin_app_setting_path
    end

    assert_response :success
    assert_select "select[name='app_setting[provider_supported_api_id]'] option" do |options|
      option_values = options.map { |option| option.attr("value") }.compact
      assert_includes option_values, supported_apis(:openai).id.to_s
      assert_includes option_values, openrouter.id.to_s
      assert_not_includes option_values, supported_apis(:xai).id.to_s
      assert_not_includes option_values, supported_apis(:example_api).id.to_s
    end
  end

  test "speech shared token hint names selected OpenRouter provider" do
    openrouter = SupportedApi.find_or_create_by!(api_base_uri: SupportedApi::OPENROUTER_BASE_URI) do |api|
      api.api_access_token = "openrouter-test-token"
      api.enabled = true
    end
    openrouter.update!(api_access_token: "openrouter-test-token", enabled: true)
    AppSetting.first.update!(provider_supported_api_id: openrouter.id)
    sign_in users(:super_user)

    AppSetting.stub(:fetch_openrouter_embedding_models, []) do
      get edit_admin_app_setting_path
    end

    assert_response :success
    assert_includes response.body, "Shared <span data-stt-settings-target=\"sharedTokenProviderName\">OpenRouter</span> key is configured."
    assert_not_includes response.body, "Shared OpenAI key is configured."
  end

  test "superuser can fetch OpenRouter speech models" do
    sign_in users(:super_user)

    AppSetting.stub(:fetch_openrouter_tts_models, [ "x-ai/grok-voice-tts-1.0", "google/gemini-tts" ]) do
      get speech_models_admin_app_setting_path(format: :turbo_stream),
          params: { api_uri: SupportedApi::OPENROUTER_BASE_URI, kind: "tts", q: "grok" }
    end

    assert_response :success
    assert_includes response.body, "x-ai/grok-voice-tts-1.0"
    assert_not_includes response.body, "google/gemini-tts"
  end

  test "superuser can fetch OpenRouter TTS voices for selected model" do
    sign_in users(:super_user)

    AppSetting.stub(:fetch_openrouter_tts_voices, [ "eve", "ara", "rex" ]) do
      get speech_voices_admin_app_setting_path(format: :turbo_stream),
          params: { api_uri: SupportedApi::OPENROUTER_BASE_URI, model: "x-ai/grok-voice-tts-1.0", q: "e" }
    end

    assert_response :success
    assert_includes response.body, "eve"
    assert_includes response.body, "rex"
    assert_not_includes response.body, "ara"
  end

  test "speech voice endpoint returns empty options for non OpenRouter providers" do
    sign_in users(:super_user)

    AppSetting.stub(:fetch_openrouter_tts_voices, ->(**_kwargs) { flunk("OpenRouter voice discovery should not run") }) do
      get speech_voices_admin_app_setting_path(format: :turbo_stream),
          params: { api_uri: supported_apis(:openai).api_base_uri, model: "gpt-4o-mini-tts" }
    end

    assert_response :success
    assert_not_includes response.body, "option"
  end

  test "speech model endpoint returns empty options for non OpenRouter providers" do
    sign_in users(:super_user)

    AppSetting.stub(:fetch_openrouter_stt_models, -> { flunk("OpenRouter model discovery should not run") }) do
      get speech_models_admin_app_setting_path(format: :turbo_stream),
          params: { api_uri: supported_apis(:openai).api_base_uri, kind: "stt" }
    end

    assert_response :success
    assert_not_includes response.body, "option"
  end

  test "outline research stub flag is ignored outside development" do
    app_setting = AppSetting.first
    sign_in users(:super_user)

    patch admin_app_setting_path, params: {
      app_setting: {
        course_outline_research_stub_enabled: "1"
      }
    }

    assert_redirected_to edit_admin_app_setting_path
    assert_nil app_setting.reload.settings["course_outline_research_stub_enabled"]
  end

  test "outline research stub flag can be updated in development" do
    app_setting = AppSetting.first
    sign_in users(:super_user)

    Rails.env.stub(:development?, true) do
      patch admin_app_setting_path, params: {
        app_setting: {
          course_outline_research_stub_enabled: "1"
        }
      }
    end

    assert_redirected_to edit_admin_app_setting_path
    assert_equal true, app_setting.reload.course_outline_research_stub_enabled
  end
end
