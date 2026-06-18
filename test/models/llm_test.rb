require "test_helper"

class LlmTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  test "ensure_api_provider_trailing_slash adds trailing slash when missing" do
    llm = Llm.create!(model: "m1", api_provider: "https://example.com", context_length: 1000)
    assert llm.api_provider.end_with?("/"), "api_provider should have trailing slash"
  end

  test "list_api_base_uri_options includes default and supported URIs" do
    options = Llm.list_api_base_uri_options
    assert options.is_a?(Array)
    assert options.any? { |display, uri| uri.to_s.include?("https://openrouter.ai") }, "Should include default OpenRouter URI"
    assert options.any? { |_display, uri| uri.to_s == SupportedApi::OPENAI_CODEX_BASE_URI }, "Should include ChatGPT Codex Responses URI"
  end

  test "list_api_base_uris excludes non-LLM providers like Exa" do
    Llm.create!(model: "exa-search", api_provider: ExaApiService::DEFAULT_BASE_URI, context_length: 1000)
    uris = Llm.list_api_base_uris
    refute_includes uris, ExaApiService::DEFAULT_BASE_URI, "Exa is not an LLM provider and should not be selectable"
  end

  test "archive sets archived_at" do
    llm = Llm.create!(model: "test-model", api_provider: "https://example.com/", context_length: 1000)
    refute llm.archived?
    llm.archive
    assert llm.archived?
    assert llm.archived_at.present?
  end

  test "unarchive clears archived_at" do
    llm = Llm.create!(model: "test-model", api_provider: "https://example.com/", archived_at: Time.current, context_length: 1000)
    assert llm.archived?
    llm.unarchive
    refute llm.archived?
    assert_nil llm.archived_at
  end

  test "cannot create duplicate model when archived exists" do
    Llm.with_archived.create!(model: "duplicate-model", api_provider: "https://example.com/", archived_at: Time.current, context_length: 1000)
    duplicate = Llm.new(model: "duplicate-model", api_provider: "https://example.com/", context_length: 1000)

    refute duplicate.valid?
    assert_includes duplicate.errors[:model], "has already been taken"
  end

  test "cannot archive LLM referenced in app_setting for image generation" do
    app_setting = AppSetting.first || AppSetting.create!(singleton: true)
    llm = Llm.create!(model: "test-model", api_provider: "https://example.com/", context_length: 1000)
    app_setting.update!(image_llm_id: llm.id)

    refute llm.archive
    assert_includes llm.errors[:archived_at], "cannot be set because this LLM is configured for image generation in app settings"

    llm.reload
    refute llm.archived?

    app_setting.update!(image_llm_id: nil)
  end

  test "cannot archive LLM referenced in app_setting for STT" do
    app_setting = AppSetting.first || AppSetting.create!(singleton: true)
    llm = Llm.create!(model: "test-model", api_provider: "https://example.com/", context_length: 1000)
    app_setting.update!(stt_model_id: llm.id)

    refute llm.archive
    assert_includes llm.errors[:archived_at], "cannot be set because this LLM is configured for speech-to-text in app settings"

    llm.reload
    refute llm.archived?

    app_setting.update!(stt_model_id: nil)
  end

  test "creating openrouter llm enqueues metadata update job" do
    assert_enqueued_jobs 0, only: UpdateOpenrouterModelMetadataJob

    assert_enqueued_jobs 1, only: UpdateOpenrouterModelMetadataJob do
      Llm.create!(model: "openrouter/model-v1", api_provider: "https://openrouter.ai/api/v1/")
    end
  end

  test "creating non openrouter llm enqueues models dev metadata update job" do
    assert_enqueued_jobs 0, only: UpdateModelsDevModelMetadataJob

    assert_enqueued_jobs 1, only: UpdateModelsDevModelMetadataJob do
      Llm.create!(model: "gpt-5", api_provider: "https://api.openai.com/v1/")
    end
  end
end
