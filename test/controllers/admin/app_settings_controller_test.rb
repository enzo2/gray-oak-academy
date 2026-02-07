require "test_helper"

class Admin::AppSettingsControllerTest < ActionDispatch::IntegrationTest
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
end
