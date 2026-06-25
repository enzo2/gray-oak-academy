require "test_helper"

class GenerationErrorPresenterTest < ActiveSupport::TestCase
  test "background-agent usage limit error advises configuring a shared provider" do
    error = BackgroundAgentConfigResolver::CodexUsageLimitError.new(
      "Codex stream request failed: status=429 ...",
      resets_at: 90.minutes.from_now,
      plan_type: "plus"
    )

    message = GenerationErrorPresenter.friendly(error)

    assert_includes message, "ChatGPT Plus usage limit"
    assert_includes message, "resets in about"
    assert_includes message, "App Settings"
    refute_includes message, "status=429"
  end

  test "personal-scope usage limit error advises switching the teacher's own model" do
    error = BackgroundAgentConfigResolver::CodexUsageLimitError.new(
      "Codex stream request failed: status=429 ...",
      resets_at: 90.minutes.from_now,
      plan_type: "plus"
    )

    message = GenerationErrorPresenter.friendly(error, scope: :personal)

    assert_includes message, "ChatGPT Plus usage limit"
    assert_includes message, "resets in about"
    assert_includes message, "Settings > LLMs"
    refute_includes message, "background runs"
    refute_includes message, "shared background-agent provider"
  end

  test "usage limit error omits the reset clause when no reset time is known" do
    error = BackgroundAgentConfigResolver::CodexUsageLimitError.new("raw", resets_at: nil, plan_type: nil)

    message = GenerationErrorPresenter.friendly(error)

    assert_includes message, "usage limit for background runs has been reached"
    refute_includes message, "resets in about"
  end

  test "usage limit error omits the reset clause when the reset time has already passed" do
    error = BackgroundAgentConfigResolver::CodexUsageLimitError.new("raw", resets_at: 5.minutes.ago, plan_type: "pro")

    message = GenerationErrorPresenter.friendly(error)

    assert_includes message, "ChatGPT Pro usage limit"
    refute_includes message, "resets in about"
  end

  test "unknown errors fall back to their own message" do
    assert_equal "boom", GenerationErrorPresenter.friendly(OpenAiError.new("boom"))
  end
end
