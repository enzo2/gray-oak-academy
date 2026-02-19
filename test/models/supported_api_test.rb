require "test_helper"

class SupportedApiTest < ActiveSupport::TestCase
  test "openai_selectable and xai_selectable use exact provider matches" do
    openai = supported_apis(:openai)
    xai = supported_apis(:xai)

    assert_equal openai, SupportedApi.openai_selectable
    assert_equal xai, SupportedApi.xai_selectable
  end

  test "openai_supported and xai_supported use canonical provider uris" do
    openai = supported_apis(:openai)
    xai = supported_apis(:xai)

    assert_equal openai, SupportedApi.openai_supported
    assert_equal xai, SupportedApi.xai_supported
  end

  test "responses_agent_selectable returns only selectable openai and xai providers" do
    selectable_ids = SupportedApi.responses_agent_selectable.pluck(:id)

    assert_includes selectable_ids, supported_apis(:openai).id
    assert_includes selectable_ids, supported_apis(:xai).id
    assert_not_includes selectable_ids, supported_apis(:example_api).id
  end

  test "find_responses_agent_selectable_by_id and base_uri only resolve supported providers" do
    openai = supported_apis(:openai)
    example_api = supported_apis(:example_api)

    assert_equal openai, SupportedApi.find_responses_agent_selectable_by_id(openai.id)
    assert_nil SupportedApi.find_responses_agent_selectable_by_id(example_api.id)
    assert_nil SupportedApi.find_responses_agent_selectable_by_id("999999")

    assert_equal openai, SupportedApi.find_responses_agent_selectable_by_base_uri("https://api.openai.com/v1")
    assert_nil SupportedApi.find_responses_agent_selectable_by_base_uri(example_api.api_base_uri)
    assert_nil SupportedApi.find_responses_agent_selectable_by_base_uri(nil)
  end
end
