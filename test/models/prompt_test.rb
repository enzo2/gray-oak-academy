require "test_helper"

class PromptTest < ActiveSupport::TestCase
  test "get_prompt raises clear error when category is missing" do
    error = assert_raises(RuntimeError) do
      Prompt.get_prompt(category: "other", user: users(:admin))
    end

    assert_includes error.message, "Prompt 'other' is missing"
    assert_includes error.message, "bin/rails db:seed"
  end
end
