require "test_helper"

class CourseOutlineResearchStubServiceTest < ActiveSupport::TestCase
  def setup
    @app_setting = AppSetting.first
    @original_env_value = ENV[CourseOutlineResearchStubService::ENV_KEY]
    @app_setting.update!(course_outline_research_stub_enabled: nil)
  end

  def teardown
    if @original_env_value.nil?
      ENV.delete(CourseOutlineResearchStubService::ENV_KEY)
    else
      ENV[CourseOutlineResearchStubService::ENV_KEY] = @original_env_value
    end
  end

  test "enabled? returns true in development when app setting is enabled" do
    @app_setting.update!(course_outline_research_stub_enabled: "1")

    Rails.env.stub(:development?, true) do
      assert CourseOutlineResearchStubService.enabled?
    end
  end

  test "enabled? returns true in development when env flag is enabled" do
    ENV[CourseOutlineResearchStubService::ENV_KEY] = "true"

    Rails.env.stub(:development?, true) do
      assert CourseOutlineResearchStubService.enabled?
    end
  end

  test "enabled? returns false outside development even when flags are enabled" do
    @app_setting.update!(course_outline_research_stub_enabled: "1")
    ENV[CourseOutlineResearchStubService::ENV_KEY] = "true"

    Rails.env.stub(:development?, false) do
      assert_not CourseOutlineResearchStubService.enabled?
    end
  end
end
