require "test_helper"
require_relative "../../app/services/image_generation_service"
require_relative "../../app/services/openai_api_service"

class ImageGenerationServiceTest < ActiveSupport::TestCase
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

    # Mock OpenaiApiService
    mock_service = Minitest::Mock.new

    # First pass response
    response1 = {
      "images" => [ { "image_url" => { "url" => "data:image/png;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" } } ], # 1x1 white pixel gif (base64) - using png mime type for test simplicity as service expects image/
      "content" => "Here is the first image"
    }

    # Second pass response (critique/regenerate)
    response2 = {
      "images" => [ { "image_url" => { "url" => "data:image/png;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" } } ],
      "content" => "Here is the improved image"
    }

    # We expect complete to be called twice.
    # Arguments matcher is tricky with Minitest::Mock, so we just return the responses.
    mock_service.expect :complete, response1 do |messages|
      messages.length == 1 && messages[0][:role] == "user"
    end

    mock_service.expect :complete, response2 do |messages|
      messages.length == 3 && messages[2][:role] == "user" # user, assistant, user
    end

    # Use stub to inject the mock
    OpenaiApiService.stub :new, mock_service do
      result = ImageGenerationService.generate(user: @user, prompt: @prompt)
      assert result.is_a?(Tempfile)
      assert File.exist?(result.path)
      # Clean up
      result.close
      result.unlink
    end

    assert_mock mock_service
  end

  test "generate handles OpenAiError from service" do
    OpenaiApiService.stub :new, ->(**kwargs) { raise OpenAiError, "API Error" } do
      assert_raises(OpenAiError) do
        ImageGenerationService.generate(user: @user, prompt: @prompt)
      end
    end
  end

  test "generate performs 1-pass generation when two_pass is false" do
    @app_setting.update!(image_generation_two_pass: false)

    # Mock OpenaiApiService
    mock_service = Minitest::Mock.new

    # First pass response
    response1 = {
      "images" => [ { "image_url" => { "url" => "data:image/png;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" } } ],
      "content" => "Here is the first image"
    }

    # We expect complete to be called exactly once
    mock_service.expect :complete, response1 do |messages|
      messages.length == 1 && messages[0][:role] == "user"
    end

    # Use stub to inject the mock
    OpenaiApiService.stub :new, mock_service do
      result = ImageGenerationService.generate(user: @user, prompt: @prompt)
      assert result.is_a?(Tempfile)
      assert File.exist?(result.path)
      # Clean up
      result.close
      result.unlink
    end

    assert_mock mock_service
  end
end
