# Wrapper for OpenAI (or compatible) Speech API calls
class SpeechService
  require "faraday/retry" # needed?
  class SpeechServiceError < StandardError; end

  def initialize(current_user:)
    @user = current_user
    # Check if speech is configured in user settings during initialization
    unless @user.settings.speech_configured?
      raise SpeechServiceError, "Speech is not configured in user settings."
    end

    @speech_access_token = @user.settings.speech_api_access_token
    @speech_base_uri = @user.settings.speech_api_base_uri.presence || "https://api.openai.com/v1/"
    @tts_model = @user.settings.tts_model_name.presence || "gpt-4o-mini-tts"
    @tts_voice = @user.settings.tts_voice_name.presence || "verse"
    @tts_instructions = @user.settings.tts_instructions.presence || "Don't be too enthusiastic. Speak in a calm and friendly tone."
    @stt_model = @user.settings.stt_model_name.presence || "gpt-4o-mini-transcribe"
    @client = create_speech_client
  end

  # There is no point using ruby-openai client for TTS, as the response time is so slow without chunked transfer encoding
  # Use Faraday directly for streaming
  def tts_stream(text, &block)
    # Use Faraday directly for streaming
    conn = Faraday.new(url: @speech_base_uri) do |faraday|
      faraday.request :authorization, "Bearer", @speech_access_token
      faraday.request :retry, { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }
      faraday.response :raise_error # Raise errors for 4xx/5xx responses
      faraday.adapter Faraday.default_adapter
    end

    # Remove any code blocks from the text
    text = text.gsub(/```.*?```/m, "")

    endpoint = "audio/speech"
    payload = {
      model: @tts_model,
      input: text,
      voice: @tts_voice,
      response_format: "aac", # Request AAC format; as opus compatibility varies
      instructions: @tts_instructions
    }.to_json

    begin
      response = conn.post(endpoint) do |req|
        req.headers["Content-Type"] = "application/json"
        req.headers["Transfer-Encoding"] = "chunked"
        req.headers["Accept"] = "audio/aac"
        req.body = payload
        req.options.timeout = 120 # Timeout for the entire request
        req.options.open_timeout = 10 # Timeout for connection

        # Faraday block for streaming response
        req.options.on_data = Proc.new do |chunk, _overall_received_bytes|
          yield chunk # Yield each chunk to the controller
        end
      end

      # Check status after streaming is complete
      unless response.success?
        error_body = response.body
        Rails.logger.error "TTS Streaming failed with status #{response.status}: #{error_body}"
        raise SpeechServiceError, "TTS Streaming failed with status #{response.status}: #{error_body}"
      end

    rescue Faraday::BadRequestError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "BadRequestError in TTS generation: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Bad Request: #{e.message}: #{error_message}"
    rescue Faraday::TimeoutError => e
      Rails.logger.error "Faraday::TimeoutError in TTS generation: #{e.message}"
      raise SpeechServiceError, "Speech API did not respond in time for TTS."
    rescue Faraday::ServerError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ServerError in TTS generation: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Server Error: #{e.message}: #{error_message}"
    rescue Faraday::ClientError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ClientError in TTS generation: #{e.message} #{error_message}"
      raise SpeechServiceError, "#{e.message}: #{error_message}"
    rescue Faraday::UnauthorizedError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::UnauthorizedError in TTS generation: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Access key was unauthorized for TTS generation: #{error_message}"
    rescue Faraday::ResourceNotFound => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ResourceNotFound error in TTS generation: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Resource not found: #{e.message}: #{error_message}"
    rescue StandardError => e
      Rails.logger.error "StandardError in TTS generation: #{e.message}"
      raise e # Re-raise other standard errors
    end
  end

  # Speech-to-Text (transcription) method
  def transcribe(audio_file)
    begin
      response = @client.audio.transcribe(
        parameters: {
          model: @stt_model,
          file: audio_file,
          response_format: "text"
        }
      )
      response # Should be the transcribed text
    rescue Faraday::BadRequestError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "BadRequestError in STT transcription: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Bad Request: #{e.message}: #{error_message}"
    rescue Faraday::TimeoutError => e
      Rails.logger.error "Faraday::TimeoutError in STT transcription: #{e.message}"
      raise SpeechServiceError, "Speech API did not respond in time for STT."
    rescue Faraday::ServerError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ServerError in STT transcription: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Server Error: #{e.message}: #{error_message}"
    rescue Faraday::ClientError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ClientError in STT transcription: #{e.message}"
      raise SpeechServiceError, "#{e.message}: #{error_message}"
    rescue Faraday::UnauthorizedError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::UnauthorizedError in STT transcription: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Access key was unauthorized for STT transcription: #{error_message}"
    rescue Faraday::ResourceNotFound => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ResourceNotFound error in STT transcription: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Resource not found: #{e.message}: #{error_message}"
    rescue StandardError => e
      Rails.logger.error "StandardError in STT transcription: #{e.message}"
      raise e # Re-raise other standard errors
    end
  end

  private

  def create_speech_client
    OpenAI::Client.new(access_token: @speech_access_token, uri_base: @speech_base_uri) do |faraday|
      retry_options = { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }
      faraday.request :retry, retry_options
      faraday.response :logger, ::Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
        logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
      end
    end
  end

  # Helper method to extract error messages from Faraday exceptions
  # Duplicated from OpenaiApiService for now. Consider moving to a shared module/concern later.
  def extract_faraday_error_message(exception)
    response_body = exception.respond_to?(:response) ? exception.response[:body] : nil
    return "Unknown error" unless response_body
    Rails.logger.error "Error response body: #{response_body}"

    parsed = if response_body.is_a?(String)
      begin
        JSON.parse(response_body)
      rescue JSON::ParserError
        return "Failed to parse error response: #{response_body}"
      end
    else
      response_body # Already parsed
    end

    if parsed.is_a?(Array)
      parsed = parsed.first
    end

    Rails.logger.debug "Parsed error response: #{parsed.inspect}"

    if parsed.is_a?(Hash) && parsed["error"].is_a?(Hash)
      parsed["error"]["message"] || parsed["error"]["status"] || "Unknown error"
    else
      "Unknown error format: #{parsed.inspect}"
    end
  end
end
