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
end
