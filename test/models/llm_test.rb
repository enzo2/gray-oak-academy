require "test_helper"

class LlmTest < ActiveSupport::TestCase
  test "ensure_api_provider_trailing_slash adds trailing slash when missing" do
    llm = Llm.create!(model: "m1", api_provider: "https://example.com", context_length: 1000)
    assert llm.api_provider.end_with?("/"), "api_provider should have trailing slash"
  end

  test "supports_audio_input? returns underlying flag" do
    llm = Llm.create!(model: "m-audio", api_provider: "https://example.com/", supports_audio_input: true, context_length: 1000)
    assert llm.supports_audio_input?
    llm.update!(supports_audio_input: false)
    refute llm.supports_audio_input?
  end

  test "list_api_base_uri_options includes default and supported URIs" do
    options = Llm.list_api_base_uri_options
    assert options.is_a?(Array)
    assert options.any? { |display, uri| uri.to_s.include?("https://openrouter.ai") }, "Should include default OpenRouter URI"
  end
end
