require "test_helper"

class AgentApiKeyTest < ActiveSupport::TestCase
  test "creates one time bearer token and authenticates active key" do
    key, token = AgentApiKey.create_with_token!(user: users(:admin), name: "Hermes")

    assert_predicate token, :present?
    assert token.start_with?("goa_live_")
    assert_equal key, AgentApiKey.authenticate(token)
    assert key.reload.last_used_at.present?
    assert_not_equal token, key.token_digest
  end

  test "revoked key cannot authenticate" do
    key, token = AgentApiKey.create_with_token!(user: users(:admin), name: "Hermes")

    key.revoke!

    assert_nil AgentApiKey.authenticate(token)
  end

  test "students cannot own agent api keys" do
    assert_raises ActiveRecord::RecordInvalid do
      AgentApiKey.create_with_token!(user: users(:student), name: "Nope")
    end
  end
end
