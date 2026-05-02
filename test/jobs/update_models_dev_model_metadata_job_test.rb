require "test_helper"

class UpdateModelsDevModelMetadataJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
  end

  test "updates openai metadata using provider host mapping" do
    llm = Llm.create!(model: "gpt-5", api_provider: "https://api.openai.com/v1/")
    clear_enqueued_jobs

    data = {
      "openai" => {
        "id" => "openai",
        "models" => {
          "gpt-5" => model_metadata(
            id: "gpt-5",
            context_length: 400_000,
            input_modalities: [ "text", "image", "pdf" ],
            output_modalities: [ "text" ],
            tool_call: true,
            structured_output: true
          )
        }
      }
    }

    requested_urls = []
    HttpJsonService.stub(:get, ->(url) {
      requested_urls << url
      data
    }) do
      UpdateModelsDevModelMetadataJob.perform_now(llm)
    end

    assert_equal [ UpdateModelsDevModelMetadataJob::MODELS_DEV_API_URL ], requested_urls

    llm.reload
    assert_equal 400_000, llm.context_length
    assert llm.supports_tool_use?
    assert llm.supports_structured_outputs?
    assert llm.supports_image_input?
    refute llm.supports_audio_input?
    refute llm.supports_image_output?
    assert llm.metadata_fetched_at.present?
  end

  test "updates chatgpt codex backend metadata using openai provider mapping" do
    llm = Llm.create!(model: "gpt-5.1-codex-max", api_provider: SupportedApi::OPENAI_CODEX_BASE_URI)
    clear_enqueued_jobs

    data = {
      "openai" => {
        "id" => "openai",
        "models" => {
          "gpt-5.1-codex-max" => model_metadata(
            id: "gpt-5.1-codex-max",
            context_length: 400_000,
            input_modalities: [ "text", "image" ],
            output_modalities: [ "text" ],
            tool_call: true,
            structured_output: true
          )
        }
      }
    }

    HttpJsonService.stub(:get, ->(_url) { data }) do
      UpdateModelsDevModelMetadataJob.perform_now(llm)
    end

    llm.reload
    assert_equal 400_000, llm.context_length
    assert llm.supports_tool_use?
    assert llm.supports_structured_outputs?
    assert llm.supports_image_input?
  end

  test "matches dated codex snapshot models to undated openai models" do
    llm = Llm.create!(model: "gpt-5.4-mini-2026-03-17", api_provider: SupportedApi::OPENAI_CODEX_BASE_URI)
    clear_enqueued_jobs

    data = {
      "openai" => {
        "id" => "openai",
        "models" => {
          "gpt-5.4-mini" => model_metadata(
            id: "gpt-5.4-mini",
            context_length: 400_000,
            input_modalities: [ "text", "image" ],
            output_modalities: [ "text" ],
            tool_call: true,
            structured_output: true
          )
        }
      }
    }

    HttpJsonService.stub(:get, ->(_url) { data }) do
      UpdateModelsDevModelMetadataJob.perform_now(llm)
    end

    assert_equal 400_000, llm.reload.context_length
  end

  test "matches dated openai snapshot models to undated openai models" do
    llm = Llm.create!(model: "gpt-5.4-2026-03-05", api_provider: "https://api.openai.com/v1/")
    clear_enqueued_jobs

    data = {
      "openai" => {
        "id" => "openai",
        "models" => {
          "gpt-5.4" => model_metadata(
            id: "gpt-5.4",
            context_length: 1_050_000,
            input_modalities: [ "text", "image", "pdf" ],
            output_modalities: [ "text" ],
            tool_call: true,
            structured_output: true
          )
        }
      }
    }

    HttpJsonService.stub(:get, ->(_url) { data }) do
      UpdateModelsDevModelMetadataJob.perform_now(llm)
    end

    assert_equal 1_050_000, llm.reload.context_length
  end

  test "bulk update skips fresh non openrouter metadata" do
    fresh = Llm.create!(
      model: "gpt-fresh-test",
      api_provider: "https://api.openai.com/v1/",
      context_length: 123_000,
      metadata_fetched_at: 1.hour.ago
    )
    stale = Llm.create!(
      model: "gpt-stale-test",
      api_provider: "https://api.openai.com/v1/",
      metadata_fetched_at: 2.days.ago
    )
    clear_enqueued_jobs

    fresh_fetched_at = fresh.metadata_fetched_at
    data = {
      "openai" => {
        "id" => "openai",
        "models" => {
          "gpt-fresh-test" => model_metadata(id: "gpt-fresh-test", context_length: 456_000),
          "gpt-stale-test" => model_metadata(id: "gpt-stale-test", context_length: 789_000)
        }
      }
    }

    HttpJsonService.stub(:get, ->(_url) { data }) do
      UpdateModelsDevModelMetadataJob.perform_now
    end

    fresh.reload
    stale.reload
    assert_equal 123_000, fresh.context_length
    assert_equal fresh_fetched_at.to_i, fresh.metadata_fetched_at.to_i
    assert_equal 789_000, stale.context_length
    assert stale.metadata_fetched_at > 1.minute.ago
  end

  test "updates metadata using compatible provider api url" do
    llm = Llm.create!(model: "deepseek-chat", api_provider: "https://api.deepseek.com/v1/")
    clear_enqueued_jobs

    data = {
      "deepseek" => {
        "id" => "deepseek",
        "api" => "https://api.deepseek.com",
        "models" => {
          "deepseek-chat" => model_metadata(
            id: "deepseek-chat",
            context_length: 128_000,
            input_modalities: [ "text" ],
            output_modalities: [ "text" ],
            tool_call: true,
            structured_output: false
          )
        }
      }
    }

    HttpJsonService.stub(:get, ->(_url) { data }) do
      UpdateModelsDevModelMetadataJob.perform_now(llm)
    end

    llm.reload
    assert_equal 128_000, llm.context_length
    assert llm.supports_tool_use?
    refute llm.supports_structured_outputs?
  end

  test "skips openrouter models" do
    llm = Llm.create!(model: "openai/gpt-5", api_provider: "https://openrouter.ai/api/v1/")
    clear_enqueued_jobs

    data = {
      "openrouter" => {
        "id" => "openrouter",
        "api" => "https://openrouter.ai/api/v1",
        "models" => {
          "openai/gpt-5" => model_metadata(id: "openai/gpt-5", context_length: 400_000)
        }
      }
    }

    HttpJsonService.stub(:get, ->(_url) { data }) do
      UpdateModelsDevModelMetadataJob.perform_now(llm)
    end

    assert_nil llm.reload.context_length
  end

  private

  def model_metadata(id:, context_length:, input_modalities: [ "text" ], output_modalities: [ "text" ], tool_call: false, structured_output: false)
    {
      "id" => id,
      "limit" => { "context" => context_length },
      "modalities" => {
        "input" => input_modalities,
        "output" => output_modalities
      },
      "tool_call" => tool_call,
      "structured_output" => structured_output
    }
  end
end
