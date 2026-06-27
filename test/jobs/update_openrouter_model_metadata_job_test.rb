require "test_helper"

class UpdateOpenrouterModelMetadataJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
    Llm.connection.reset_pk_sequence!("llms")
  end

  test "updates metadata for an array of llms" do
    llm1 = Llm.create!(model: "google/gemini-3-pro-image-preview", api_provider: "https://openrouter.ai/api/v1/")
    llm2 = Llm.create!(model: "google/gemini-3.1-flash-image-preview", api_provider: "https://openrouter.ai/api/v1/")
    clear_enqueued_jobs

    response = {
      "data" => {
        "architecture" => {
          "input_modalities" => [ "text", "image" ],
          "output_modalities" => [ "text", "image" ]
        },
        "endpoints" => [
          {
            "context_length" => 128_000,
            "supported_parameters" => [ "tools", "tool_choice", "structured_outputs" ]
          }
        ]
      }
    }

    requested_urls = []

    HttpJsonService.stub(:get, ->(url) {
      requested_urls << url
      response
    }) do
      UpdateOpenrouterModelMetadataJob.perform_now([ llm1, llm2 ])
    end

    assert_equal(
      [
        "https://openrouter.ai/api/v1/models/google/gemini-3-pro-image-preview/endpoints",
        "https://openrouter.ai/api/v1/models/google/gemini-3.1-flash-image-preview/endpoints"
      ].sort,
      requested_urls.sort
    )

    [ llm1.reload, llm2.reload ].each do |llm|
      assert_equal 128_000, llm.context_length
      assert_equal [ "tools", "tool_choice", "structured_outputs" ], llm.supported_parameters
      assert llm.supports_tool_use?
      assert llm.supports_structured_outputs?
      assert llm.supports_image_input?
      assert llm.supports_image_output?
      assert llm.metadata_fetched_at.present?
    end
  end

  test "updates metadata from OpenRouter Images API when model is image-only" do
    openrouter = SupportedApi.find_or_create_by!(api_base_uri: SupportedApi::OPENROUTER_BASE_URI)
    openrouter.update!(api_access_token: "openrouter-test-token", enabled: true)
    llm = Llm.create!(model: "openai/gpt-image-1", api_provider: "https://openrouter.ai/api/v1/")
    clear_enqueued_jobs

    image_models = [
      {
        "id" => "openai/gpt-image-1",
        "architecture" => {
          "input_modalities" => [ "text", "image" ],
          "output_modalities" => [ "image" ]
        },
        "supported_parameters" => {
          "quality" => { "type" => "enum", "values" => [ "auto", "high" ] },
          "n" => { "type" => "range", "min" => 1, "max" => 10 }
        }
      }
    ]
    endpoints_response = {
      "id" => "openai/gpt-image-1",
      "endpoints" => [
        {
          "supported_parameters" => {
            "quality" => { "type" => "enum", "values" => [ "auto", "high" ] },
            "n" => { "type" => "range", "min" => 1, "max" => 10 }
          }
        }
      ]
    }

    AppSetting.stub(:fetch_openrouter_image_model_data, image_models) do
      HttpJsonService.stub(:get, ->(url, headers: {}) {
        assert_equal "https://openrouter.ai/api/v1/images/models/openai/gpt-image-1/endpoints", url
        assert_equal "Bearer openrouter-test-token", headers["Authorization"]
        endpoints_response
      }) do
        UpdateOpenrouterModelMetadataJob.perform_now(llm)
      end
    end

    llm.reload
    assert_equal [ "quality", "n" ], llm.supported_parameters
    assert llm.supports_image_input?
    assert llm.supports_image_output?
    assert llm.metadata_fetched_at.present?
  end

  test "updates image metadata when endpoint supported parameters are arrays" do
    openrouter = SupportedApi.find_or_create_by!(api_base_uri: SupportedApi::OPENROUTER_BASE_URI)
    openrouter.update!(api_access_token: "openrouter-test-token", enabled: true)
    llm = Llm.create!(model: "openai/gpt-image-array", api_provider: "https://openrouter.ai/api/v1/")
    clear_enqueued_jobs

    image_models = [
      {
        "id" => "openai/gpt-image-array",
        "architecture" => {
          "input_modalities" => [ "text" ],
          "output_modalities" => [ "image" ]
        },
        "supported_parameters" => [ "quality", "n", "seed" ]
      }
    ]
    endpoints_response = {
      "id" => "openai/gpt-image-array",
      "endpoints" => [
        { "supported_parameters" => [ "quality", "n", "seed" ] },
        { "supported_parameters" => [ "quality", "n" ] }
      ]
    }

    AppSetting.stub(:fetch_openrouter_image_model_data, image_models) do
      HttpJsonService.stub(:get, endpoints_response) do
        UpdateOpenrouterModelMetadataJob.perform_now(llm)
      end
    end

    llm.reload
    assert_equal [ "quality", "n" ], llm.supported_parameters
    refute llm.supports_image_input?
    assert llm.supports_image_output?
    assert llm.metadata_fetched_at.present?
  end
end
