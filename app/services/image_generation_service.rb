class ImageGenerationService
  # Generates images using an OpenRouter image-capable LLM in a two-pass flow:
  # 1) Generate initial image from prompt
  # 2) Re-prompt to check/regenerate for misspellings or factual errors
  #
  # Returns a Tempfile containing the processed JPEG image.

  def self.generate(user:, prompt:)
    raise ArgumentError, "Missing required parameter: user" unless user
    raise ArgumentError, "Missing required parameter: prompt" unless prompt.present?

    unless AppSetting.image_generation_configured?
      raise OpenAiError, "Image generation is not configured."
    end

    app_setting = AppSetting.settings
    llm = app_setting&.image_llm
    token = app_setting&.image_effective_token

    unless llm.api_provider&.include?("openrouter.ai")
      raise OpenAiError, "Only OpenRouter is supported for image generation."
    end

    # Build an explicit prompt including size/count hints to encourage single image output
    prompt_with_hints = prompt + "Return exactly 1 image. If you include any text in the image, ensure it is spelled correctly."

    client = OpenaiApiService.new(
      current_user: user,
      base_uri: llm.api_provider,
      access_token: token,
      model: llm.model,
      image_generation: true
    )

    # First pass
    messages = [
      { role: "user", content: prompt_with_hints }
    ]
    Rails.logger.debug "ImageGenerationService: sending first-pass generation to #{llm.model}"
    msg1 = client.complete(messages, temperature: 0.5)
    unless msg1.is_a?(Hash)
      raise OpenAiError, "Unexpected response from image model"
    end

    images1 = msg1["images"] || []
    img1 = images1.first
    img1_url = img1.dig("image_url", "url")
    content1 = msg1["content"].to_s

    unless img1_url.present? && img1_url.start_with?("data:image/")
      raise OpenAiError, "Image model returned no images on first pass."
    end

    # Second pass: ask the model to check and regenerate if needed.
    critique_instructions = "Thanks. Please review the image you just generated for errors such as misspellings, incorrect labels, or factual mistakes relative to the original prompt. Regenerate a corrected and improved image (even if you think the original is OK)."
    content_json = [ { "type": "text", "text": content1 } ]
    content_json << { "type": "image_url", "image_url": { "url": img1_url } }
    messages << { role: "assistant", content: content_json }
    messages << { role: "user", content: critique_instructions }

    Rails.logger.debug "ImageGenerationService: sending second-pass critique/regeneration to #{llm.model}"
    Rails.logger.debug "messages: #{messages}"
    msg2 = client.complete(messages, temperature: 0.5)
    unless msg2.is_a?(Hash)
      Rails.logger.warn "ImageGenerationService: second pass returned no image; falling back to first pass images"
      final_images = images1
      final_content = content1
    else
      images2 = msg2["images"] || []
      final_images = images2.any? ? images2 : images1
      final_content = msg2["content"].to_s.presence || content1
    end

    Rails.logger.debug "Content from image generation: #{final_content}"

    # Process and return a single Tempfile for the final image
    base64_url = final_images.first&.dig("image_url", "url")
    unless base64_url.present? && base64_url.start_with?("data:image/")
      raise OpenAiError, "Image generation failed: invalid image data"
    end

    # Extract mime and base64 payload
    match = base64_url.match(/\Adata:(image\/[a-zA-Z0-9.+-]+);base64,(.+)/)
    unless match
      raise OpenAiError, "Malformed data URL"
    end

    base64_data = match.captures.second

    begin
      decoded_data = Base64.strict_decode64(base64_data)
      unless decoded_data && decoded_data.length > 0
        raise OpenAiError, "Invalid base64 payload"
      end

      # Size check to prevent huge images
      if decoded_data.length > 10_000_000 # ~10MB limit
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
  rescue OpenAiError => e
    Rails.logger.error "ImageGenerationService OpenAiError: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "ImageGenerationService Error: #{e.class}: #{e.message}"
    raise OpenAiError, "Image generation failed: #{e.message}"
  end
end
