require "test_helper"

class SettingInheritanceTest < ActiveSupport::TestCase
  def setup
    @teacher = users(:admin)
    @student = users(:student)
    @teacher_setting = @teacher.setting
    @student_setting = @student.setting

    # Ensure teacher has some settings
    @teacher_setting.update!(
      llm_model_name: "teacher-model",
      llm_api_base_uri: "https://teacher.api/",
      llm_api_access_token: "teacher-token",
      reasoning_model_name: "teacher-reasoning-model"
    )

    # Ensure student's settings are initially blank for inheritance test
    @student_setting.update!(
      llm_model_name: nil,
      llm_api_base_uri: nil,
      llm_api_access_token: nil,
      reasoning_model_name: nil
    )
  end

  test "student inherits llm_model_name from teacher" do
    assert_equal @teacher_setting.llm_model_name, @student_setting.llm_model_name
  end

  test "student inherits llm_api_base_uri from teacher" do
    assert_equal @teacher_setting.llm_api_base_uri, @student_setting.llm_api_base_uri
  end

  test "student inherits llm_api_access_token from teacher" do
    assert_equal @teacher_setting.llm_api_access_token, @student_setting.llm_api_access_token
  end

  test "student inherits reasoning_model_name from teacher" do
    assert_equal @teacher_setting.reasoning_model_name, @student_setting.reasoning_model_name
  end

  test "student inherits OpenAI OAuth credential fields from teacher" do
    @teacher_setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      openai_oauth_access_token: "teacher-oauth-token",
      openai_oauth_refresh_token: "teacher-oauth-refresh",
      openai_oauth_expires_at: 1.hour.from_now.iso8601,
      openai_oauth_email: "teacher@example.com"
    )

    inherited = @student.reload.settings
    assert_equal "teacher-oauth-token", inherited.openai_oauth_access_token
    assert_equal "teacher-oauth-refresh", inherited.openai_oauth_refresh_token
    assert_equal "teacher@example.com", inherited.openai_oauth_email
    assert inherited.openai_oauth_expires_at.present?
  end

  test "llm_configured? returns true if teacher's settings are configured" do
    assert @teacher_setting.llm_configured?
    assert @student_setting.llm_configured?
  end

  test "llm_configured? returns true via inherited OpenAI OAuth when API key is unset" do
    @teacher_setting.update!(
      llm_api_base_uri: SupportedApi::OPENAI_CODEX_BASE_URI,
      llm_model_name: "teacher-model",
      llm_api_access_token: nil,
      openai_oauth_access_token: "teacher-oauth-token",
      openai_oauth_refresh_token: "teacher-oauth-refresh",
      openai_oauth_expires_at: 1.hour.from_now.iso8601
    )
    @student_setting.update!(llm_api_access_token: nil)

    assert @teacher_setting.llm_configured?
    assert @student_setting.llm_configured?
  end
end
