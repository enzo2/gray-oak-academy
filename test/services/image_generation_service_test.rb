require "test_helper"
require_relative "../../app/services/image_generation_service"

class ImageGenerationServiceTest < ActiveSupport::TestCase
  TINY_IMAGE_B64 = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"

  def setup
    @user = users(:admin)
    @prompt = "A test image"
    # Ensure AppSetting is configured for image generation
    # We need a provider, token, and image_llm
    @provider = supported_apis(:example_api)
    # The fixture example_api uri is https://api.example.com/, but ImageGenerationService enforces OpenRouter
    @provider.update!(api_base_uri: "https://openrouter.ai/api/v1/", api_access_token: "test_token")

    @llm = llms(:one)
    # Ensure LLM is set as supporting image output and provider is openrouter
    @llm.update!(
      api_provider: "https://openrouter.ai/api/v1/",
      model: "image-model",
      supports_image_output: true,
      supports_image_input: true
    )

    @app_setting = AppSetting.first
    @app_setting.update!(image_llm_id: @llm.id)
  end

  test "generate raises error if not configured" do
    @app_setting.update!(image_llm_id: nil)
    assert_raises(OpenAiError) do
      ImageGenerationService.generate(user: @user, prompt: @prompt)
    end
  end

  test "generate performs 2-pass generation and returns tempfile" do
    @app_setting.update!(image_generation_two_pass: true)

    requests = []
    responses = [ image_response(cost: 0.04), image_response(cost: 0.05) ]

    ImageGenerationService.stub :post_openrouter_images, ->(token:, payload:) {
      requests << { token: token, payload: payload }
      responses.shift
    } do
      result = ImageGenerationService.generate(user: @user, prompt: @prompt)
      assert result.is_a?(Tempfile)
      assert File.exist?(result.path)
      result.close
      result.unlink
    end

    assert_equal 2, requests.length
    assert_equal "test_token", requests.first[:token]
    assert_equal "image-model", requests.first[:payload][:model]
    assert_match(/Return exactly 1 image/, requests.first[:payload][:prompt])
    assert_nil requests.first[:payload][:input_references]
    assert_equal 1, requests.first[:payload][:n]

    references = requests.second[:payload][:input_references]
    assert_equal "image_url", references.first[:type]
    assert_match(/\Adata:image\/png;base64,/, references.first[:image_url][:url])
    assert_match(/Regenerate a corrected and improved image/, requests.second[:payload][:prompt])
    assert_equal 2, Completion.where(model: "image-model", api_provider: "https://openrouter.ai/api/v1/").count
  end

  test "generate falls back to first-pass image when second pass returns no image" do
    @app_setting.update!(image_generation_two_pass: true)

    requests = []
    responses = [
      image_response(cost: 0.04),
      {
        "data" => [],
        "usage" => {
          "prompt_tokens" => 1,
          "completion_tokens" => 2,
          "total_tokens" => 3,
          "cost" => 0.01
        }
      }
    ]

    ImageGenerationService.stub :post_openrouter_images, ->(token:, payload:) {
      requests << { token: token, payload: payload }
      responses.shift
    } do
      result = ImageGenerationService.generate(user: @user, prompt: @prompt)
      assert result.is_a?(Tempfile)
      assert File.exist?(result.path)
      result.close
      result.unlink
    end

    assert_equal 2, requests.length
    assert_equal 2, Completion.where(model: "image-model", api_provider: "https://openrouter.ai/api/v1/").count
  end

  test "generate handles OpenAiError from service" do
    ImageGenerationService.stub :post_openrouter_images, ->(**_kwargs) { raise OpenAiError, "API Error" } do
      assert_raises(OpenAiError) do
        ImageGenerationService.generate(user: @user, prompt: @prompt)
      end
    end
  end

  test "generate performs 1-pass generation when two_pass is false" do
    @app_setting.update!(image_generation_two_pass: false)

    requests = []

    ImageGenerationService.stub :post_openrouter_images, ->(token:, payload:) {
      requests << { token: token, payload: payload }
      image_response
    } do
      result = ImageGenerationService.generate(user: @user, prompt: @prompt)
      assert result.is_a?(Tempfile)
      assert File.exist?(result.path)
      result.close
      result.unlink
    end

    assert_equal 1, requests.length
    assert_nil requests.first[:payload][:input_references]
  end

  test "generate is not configured when two pass model lacks image input" do
    @app_setting.update!(image_generation_two_pass: true)
    @llm.update!(supports_image_input: false, supports_image_output: true)

    error = assert_raises(OpenAiError) do
      ImageGenerationService.generate(user: @user, prompt: @prompt)
    end

    assert_match(/not configured/, error.message)
  end

  private

  def image_response(cost: 0.04)
    {
      "data" => [ { "b64_json" => TINY_IMAGE_B64 } ],
      "usage" => {
        "prompt_tokens" => 0,
        "completion_tokens" => 4175,
        "total_tokens" => 4175,
        "cost" => cost
      }
    }
  end
end
