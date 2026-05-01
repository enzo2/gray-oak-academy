require "test_helper"

class UpdateOpenrouterModelMetadataJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
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
end
