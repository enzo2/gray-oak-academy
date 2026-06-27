class ImageGenerationService
  require "net/http"
  require "uri"

  MAX_IMAGE_BYTES = 10_000_000

  # Generates images using the OpenRouter Images API in a two-pass flow:
  # 1) Generate initial image from prompt
  # 2) Optionally pass the first image back as a reference and regenerate
  #
  # Returns a Tempfile containing the processed JPEG image.

  def self.generate(user:, prompt:, conversation: nil)
    raise ArgumentError, "Missing required parameter: user" unless user
    raise ArgumentError, "Missing required parameter: prompt" unless prompt.present?

    unless AppSetting.image_generation_configured?
      raise OpenAiError, "Image generation is not configured."
    end

    app_setting = AppSetting.settings
    llm = app_setting&.image_llm
    token = app_setting&.image_effective_token
    two_pass = app_setting&.image_generation_two_pass

    unless llm.api_provider&.include?("openrouter.ai")
      raise OpenAiError, "Only OpenRouter is supported for image generation."
    end

    # Build an explicit prompt including size/count hints to encourage single image output
    prompt_with_hints = "#{prompt}\n\nReturn exactly 1 image. If you include any text in the image, ensure it is spelled correctly."

    # First pass
    Rails.logger.debug "ImageGenerationService: sending first-pass generation to #{llm.model}"
    response1 = create_openrouter_image(
      user: user,
      conversation: conversation,
      token: token,
      model: llm.model,
      prompt: prompt_with_hints
    )
    image1_data_url = first_image_data_url(response1)

    if two_pass
      critique_prompt = <<~PROMPT.squish
        Review the reference image for misspellings, incorrect labels, or factual mistakes relative to this original prompt:
        #{prompt}
        Regenerate a corrected and improved image, even if the reference image is already acceptable.
      PROMPT

      Rails.logger.debug "ImageGenerationService: sending second-pass critique/regeneration to #{llm.model}"
      response2 = create_openrouter_image(
        user: user,
        conversation: conversation,
        token: token,
        model: llm.model,
        prompt: critique_prompt,
        input_references: [ image1_data_url ]
      )
      final_image_data_url = maybe_first_image_data_url(response2) || image1_data_url
    else
      final_image_data_url = image1_data_url
    end

    process_image_data_url(final_image_data_url)
  rescue OpenAiError => e
    Rails.logger.error "ImageGenerationService OpenAiError: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "ImageGenerationService Error: #{e.class}: #{e.message}"
    raise OpenAiError, "Image generation failed: #{e.message}"
  end

  def self.create_openrouter_image(user:, conversation:, token:, model:, prompt:, input_references: nil)
    check_cost_limits(user: user, conversation: conversation)

    payload = {
      model: model,
      prompt: prompt,
      n: 1
    }

    if input_references.present?
      payload[:input_references] = input_references.map do |url|
        {
          type: "image_url",
          image_url: { url: url }
        }
      end
    end

    response = post_openrouter_images(token: token, payload: payload)
    log_completion(user: user, conversation: conversation, model: model, usage: response["usage"])
    response
  end

  def self.post_openrouter_images(token:, payload:)
    uri = URI.join(SupportedApi::OPENROUTER_BASE_URI, "images")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OpenaiClientDefaults.timeout_seconds
    http.read_timeout = OpenaiClientDefaults.timeout_seconds

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    openrouter_attribution_headers.each { |key, value| request[key] = value }
    request.body = payload.to_json

    response = http.request(request)
    parsed = JSON.parse(response.body)

    unless response.is_a?(Net::HTTPSuccess)
      raise OpenAiError, "OpenRouter Images API request failed: #{extract_error_message(parsed).presence || response.message}"
    end

    parsed
  rescue JSON::ParserError => e
    raise OpenAiError, "OpenRouter Images API returned invalid JSON: #{e.message}"
  rescue OpenAiError
    raise
  rescue StandardError => e
    raise OpenAiError, "OpenRouter Images API request failed: #{e.message}"
  end

  def self.first_image_data_url(response)
    maybe_first_image_data_url(response) || raise(OpenAiError, "Image model returned no images.")
  end

  def self.maybe_first_image_data_url(response)
    image = response&.dig("data", 0)
    base64_data = image&.dig("b64_json")
    media_type = image&.dig("media_type").presence || "image/png"

    return nil unless base64_data.present? && media_type.start_with?("image/")

    "data:#{media_type};base64,#{base64_data}"
  end

  def self.process_image_data_url(base64_url)
    match = base64_url.match(/\Adata:(image\/[a-zA-Z0-9.+-]+);base64,(.+)\z/m)
    raise OpenAiError, "Malformed data URL" unless match

    base64_data = match.captures.second

    begin
      decoded_data = Base64.strict_decode64(base64_data)
      unless decoded_data && decoded_data.length > 0
        raise OpenAiError, "Invalid base64 payload"
      end

      # Size check to prevent huge images
      if decoded_data.length > MAX_IMAGE_BYTES
        raise OpenAiError, "Oversized image payload: #{decoded_data.length} bytes"
      end

      # Create Tempfile for original
      temp_original = Tempfile.new([ "generated-original", ".bin" ])
      temp_original.binmode
      temp_original.write(decoded_data)
      temp_original.rewind

      # Process: resize and convert to JPEG
      processed_path = ImageProcessing::Vips
        .source(temp_original.path)
        .resize_to_limit(1024, 1024)
        .convert("jpg")
        .saver(quality: 85)
        .call

      # Create Tempfile for processed image
      timestamp = Time.current.to_i
      temp_processed = Tempfile.new([ "generated-#{timestamp}", ".jpg" ])
      temp_processed.binmode
      File.open(processed_path, "rb") { |f| temp_processed.write(f.read) }
      temp_processed.rewind

      # Clean up original temp
      temp_original.close
      temp_original.unlink

      Rails.logger.debug "Image processed successfully: #{temp_processed.path}"

      temp_processed
    rescue ArgumentError => e
      temp_original&.close
      temp_original&.unlink
      raise OpenAiError, "Decode error: #{e.message}"
    rescue => e
      temp_original&.close
      temp_original&.unlink
      raise OpenAiError, "Error processing image: #{e.message}"
    end
  end

  def self.log_completion(user:, conversation:, model:, usage:)
    Completion.create(
      conversation: conversation,
      user: conversation ? nil : user,
      model: model,
      api_provider: SupportedApi::OPENROUTER_BASE_URI,
      prompt_tokens: usage&.dig("prompt_tokens")&.to_i,
      cached_tokens: usage&.dig("prompt_tokens_details", "cached_tokens")&.to_i,
      completion_tokens: usage&.dig("completion_tokens")&.to_i,
      reasoning_tokens: usage&.dig("completion_tokens_details", "reasoning_tokens")&.to_i,
      total_tokens: usage&.dig("total_tokens")&.to_i,
      total_cost: usage_total_cost(usage)
    )
  end

  def self.usage_total_cost(usage)
    LlmUsageAccountingService.usage_total_cost(usage)
  end

  def self.check_cost_limits(user:, conversation:)
    LlmUsageAccountingService.enforce_cost_limits!(user: user, conversation: conversation)
  end

  def self.openrouter_attribution_headers
    {
      "X-Title" => "Gray Oak Academy",
      "HTTP-Referer" => Rails.env.production? ? "https://#{ENV.fetch('APP_HOST')}" : nil
    }.compact
  end

  def self.extract_error_message(response)
    return nil unless response.is_a?(Hash)

    error = response["error"]
    return error if error.is_a?(String)
    return error["message"] if error.is_a?(Hash)

    nil
  end
end
