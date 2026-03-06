require "test_helper"

class SettingTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @setting = @user.settings || @user.create_setting!

    # Standard Shared API setup
    @api_uri = "https://openrouter.ai/api/v1/"
    @supported_api = SupportedApi.create!(
      api_base_uri: @api_uri,
      enabled: true,
      api_access_token: "shared_token"
    )

    @active_model = Llm.create!(
      model: "active-model",
      api_provider: @api_uri,
      context_length: 1000
    )

    @archived_model = Llm.create!(
      model: "archived-model",
      api_provider: @api_uri,
      context_length: 1000,
      archived_at: Time.current
    )
  end

  test "permits custom model if custom token is provided" do
    @setting.llm_api_base_uri = @api_uri
    @setting.llm_api_access_token = "my-secret-key"
    @setting.llm_model_name = "random-custom-model"

    assert @setting.valid?
  end

  test "permits active model with shared token" do
    @setting.llm_api_base_uri = @api_uri
    @setting.llm_api_access_token = ""
    @setting.llm_model_name = "active-model"

    assert @setting.valid?
  end

  test "rejects archived model with shared token" do
    @setting.llm_api_base_uri = @api_uri
    @setting.llm_api_access_token = ""
    @setting.llm_model_name = "archived-model"

    refute @setting.valid?
    assert_includes @setting.errors[:llm_model_name], "is not available or has been archived for this shared API. Add an override token to use new models."
  end

  test "rejects non-existent model with shared token" do
    @setting.llm_api_base_uri = @api_uri
    @setting.llm_api_access_token = ""
    @setting.llm_model_name = "ghost-model"

    refute @setting.valid?
    assert_includes @setting.errors[:llm_model_name], "is not available or has been archived for this shared API. Add an override token to use new models."
  end

  test "validates reasoning model as well" do
    @setting.llm_api_base_uri = @api_uri
    @setting.llm_api_access_token = ""
    @setting.llm_model_name = "active-model"
    @setting.reasoning_model_name = "archived-model"

    refute @setting.valid?
    assert_includes @setting.errors[:reasoning_model_name], "is not available or has been archived for this shared API. Add an override token to use new models."
  end

  test "rejects unauthorized model when falling back to ENV credentials" do
    # Simulate ENV configuration
    env_uri = "https://env-provider.com/v1/"
    ENV["OPENAI_API_BASE_URL"] = env_uri
    ENV["OPENAI_API_KEY"] = "env_key"

    # User leaves settings blank to use ENV
    @setting.llm_api_base_uri = ""
    @setting.llm_api_access_token = ""
    @setting.llm_model_name = "expensive-env-model"

    # Create the model record so it technically "exists", but don't add it to Llm table (or add it as archived/restricted if needed)
    # Actually, the logic is: "If it's a shared API, the model MUST exist in Llm table and NOT be archived."
    # So if we simply don't create an Llm record for "expensive-env-model", it should fail validation.

    # Currently, this test would FAIL (i.e., assert @setting.valid? would be true) because the loop hole exists.
    # We want to assert that it is INVALID.

    refute @setting.valid?, "Should reject unauthorized model when using ENV credentials"
    assert_includes @setting.errors[:llm_model_name], "is not available or has been archived for this shared API. Add an override token to use new models."
  ensure
    # Cleanup ENV
    ENV.delete("OPENAI_API_BASE_URL")
    ENV.delete("OPENAI_API_KEY")
  end

  test "permits custom model when OpenAI OAuth credential is present" do
    @setting.llm_api_base_uri = SupportedApi::OPENAI_CODEX_BASE_URI
    @setting.llm_api_access_token = ""
    @setting.openai_oauth_access_token = "oauth-token"
    @setting.openai_oauth_expires_at = 1.hour.from_now.iso8601
    @setting.llm_model_name = "non-catalog-openai-model"

    assert @setting.valid?
  end

  test "llm_configured? is true when OpenAI OAuth credential is present" do
    @setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: "custom-openai-model",
      llm_api_access_token: nil,
      openai_oauth_access_token: "oauth-token",
      openai_oauth_expires_at: 1.hour.from_now.iso8601
    )

    assert @setting.llm_configured?
  end

  test "llm_configured? is false for codex provider when only API key is present" do
    @setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: "custom-openai-model",
      llm_api_access_token: "personal-openai-key",
      openai_oauth_access_token: nil,
      openai_oauth_refresh_token: nil,
      openai_oauth_expires_at: nil
    )

    refute @setting.llm_configured?
  end
end
