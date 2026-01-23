require "test_helper"

class CompletionTest < ActiveSupport::TestCase
  setup do
    @llm = Llm.create!(model: "test-model", api_provider: "https://example.com/", context_length: 1000)
    @user = users(:admin)
    @conversation = Conversation.create!(user: @user, title: "Test")
  end

  test "valid completion" do
    completion = Completion.new(
      llm: @llm,
      conversation: @conversation,
      user: @user,
      model: "test-model",
      api_provider: "https://example.com/",
      prompt_tokens: 100,
      completion_tokens: 50,
      total_tokens: 150
    )
    assert completion.valid?
  end

  test "usage data includes archived LLMs" do
    archived_llm = Llm.with_archived.create!(
      model: "archived-model",
      api_provider: "https://example.com/",
      context_length: 1000,
      archived_at: Time.current
    )

    Completion.create!(
      llm: archived_llm,
      conversation: @conversation,
      user: @user,
      model: "archived-model",
      api_provider: "https://example.com/",
      prompt_tokens: 10,
      completion_tokens: 5,
      total_tokens: 15
    )

    usage_data = Completion.all_time_usage_data.to_a
    assert usage_data.any? { |row| row.model == "archived-model" }
  end
end
