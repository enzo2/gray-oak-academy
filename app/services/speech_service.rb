# Wrapper for OpenAI (or compatible) Speech API calls
class SpeechService
  require "faraday/retry" # needed?
  require "open3"
  include ActionView::Helpers::SanitizeHelper
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
    @tts_instructions = @user.settings.tts_instructions.presence || "Speak in a calm and friendly tone."
    @stt_model = @user.settings.stt_model_name.presence || "gpt-4o-mini-transcribe"
    @client = create_speech_client
  end

  # There is no point using ruby-openai client for TTS, as the response time is so slow without chunked transfer encoding.
  # To stream the response to the user in realtime, we can:
  # 1) Use Faraday directly for streaming from the Speech API. Start processing chunks immediately.
  # 2) Send the chunks to ffmpeg to transmux to WebM/opus that the browser can stream with MSE (https://github.com/w3c/media-source/issues/245)
  # 3) Yield the audio chunks to the controller so they can be re-streamed using ActionController:Live.
  # 4) The Stimulus controller plays the stream as soon as it starts receiving chunks.
  def tts_stream(text, &block)
    text = sanitize_tts_text(text) # in case wasn't done yet
    return if text.blank?

    conn = Faraday.new(url: @speech_base_uri) do |faraday|
      faraday.request :authorization, "Bearer", @speech_access_token
      faraday.request :retry, { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }
      faraday.response :raise_error # Raise errors for 4xx/5xx responses
      faraday.adapter Faraday.default_adapter
    end

    endpoint = "audio/speech"
    payload = {
      model: @tts_model,
      input: text,
      voice: @tts_voice,
      response_format: "opus", # OpenAI returns Opus in Ogg container.
      instructions: @tts_instructions
    }.to_json

    # Transmux the response to WebM format using ffmpeg to allow use of Opus codec with MSE on all browsers
    # ffmpeg: read from stdin, write to stdout
    ffmpeg_command = [ "ffmpeg", "-i", "pipe:0", "-vn", "-c:a", "copy", "-f", "webm", "-nostdin", "-loglevel", "error", "pipe:1" ]
    ffmpeg_stderr_output = "" # Variable to capture ffmpeg errors
    @client_disconnected = false # Flag to track client disconnection

    # Start ffmpeg process
    begin
      # Use Open3 to manage ffmpeg process and its pipes
      Open3.popen3(*ffmpeg_command) do |ffmpeg_stdin, ffmpeg_stdout, ffmpeg_stderr, wait_thr|
        ffmpeg_stdin.binmode # Ensure binary mode for pipes
        ffmpeg_stdout.binmode
        Rails.logger.info "SpeechService: Started ffmpeg process with PID #{wait_thr.pid}"

        # Thread to read ffmpeg stderr to capture errors
        stderr_thread = Thread.new do
          begin
            ffmpeg_stderr_output = ffmpeg_stderr.read
          ensure
            ffmpeg_stderr.close # Close stderr pipe when done reading
          end
        end

        # Thread to read from ffmpeg's stdout and yield chunks to the controller
        stdout_thread = Thread.new do
          begin
            while (chunk = ffmpeg_stdout.read(8192)) # Read in chunks
              begin
                yield chunk # Yield the transcoded chunk
              rescue ActionController::Live::ClientDisconnected
                # Client disconnected during yield, likely due to user stopping/starting another stream.
                # This is expected, log and break the loop to allow cleanup.
                @client_disconnected = true
                Rails.logger.info "Client disconnected during yield in SpeechService stdout_thread. Stopping stream."
                break # Exit the while loop
              end
            end
          rescue IOError => e
            # Ignore "stream closed" errors which can happen during cleanup
            Rails.logger.warn "IOError reading ffmpeg stdout (expected on close): #{e.message}"
          ensure
            # Ensure the pipe is closed even if an error occurred before the loop finished
            ffmpeg_stdout.close unless ffmpeg_stdout.closed?
          end
        end

        # Make the API request with streaming response handling
        response = conn.post(endpoint) do |req|
          req.headers["Content-Type"] = "application/json"
          req.headers["Transfer-Encoding"] = "chunked" # Not needed, but included for clarity
          req.body = payload
          req.options.timeout = 120 # Timeout for the entire request
          req.options.open_timeout = 10 # Timeout for connection

          # Use Faraday's on_data callback to stream response body directly to ffmpeg
          req.options.on_data = Proc.new do |chunk, _overall_received_bytes|
            # Skip writing if client disconnected or pipe closed
            next if @client_disconnected || ffmpeg_stdin.closed?

            begin
              ffmpeg_stdin.write(chunk)
            rescue Errno::EPIPE
              Rails.logger.debug "ffmpeg stdin pipe closed prematurely."
            end
          end
        end

        ffmpeg_stdin.close # After API response finishes, close ffmpeg's stdin to signal EOF
        ffmpeg_status = wait_thr.value # Wait for ffmpeg process to finish
        stdout_thread.join # Wait for reader threads to finish
        stderr_thread.join
        Rails.logger.info "ffmpeg process and reader threads finished"

        # Check ffmpeg exit status
        unless ffmpeg_status.success? || @client_disconnected
          Rails.logger.error "ffmpeg failed with status: #{ffmpeg_status.exitstatus}. Stderr: #{ffmpeg_stderr_output}"
          raise SpeechServiceError, "Audio processing failed (ffmpeg exited with status #{ffmpeg_status.exitstatus}). Error: #{ffmpeg_stderr_output.lines.last || 'Unknown ffmpeg error'}"
        else
          Rails.logger.info "ffmpeg completed successfully"
        end

        # Also check the original API response status *after* streaming attempt
        unless response.success?
          Rails.logger.error "TTS API request failed post-stream with status #{response.status}"
          Rails.logger.error "Error details: #{response.body}" if response.body.present?
          # Prefer ffmpeg error if it exists, otherwise raise API error
          raise SpeechServiceError, "TTS API request failed with status #{response.status}" unless ffmpeg_status.success?
        end
      end # Open3.popen3

      Rails.logger.info("TTS request finished")
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
    rescue Errno::ENOENT => e
      # Handle case where ffmpeg command is not found
      Rails.logger.error "ffmpeg command not found: #{e.message}"
      raise SpeechServiceError, "ffmpeg command failed. Please ensure it's installed and in the PATH."
    rescue SpeechServiceError => e
      raise e # Re-raise our specific errors
    rescue StandardError => e
      Rails.logger.error "StandardError in TTS streaming/processing: #{e.message}"
      raise SpeechServiceError, "An unexpected error occurred during TTS streaming/processing: #{e.message}" # Re-raise other standard errors
    end
  end

  # Speech-to-Text (transcription) method
  def transcribe(audio_file)
    begin
      response = @client.audio.transcribe(
        parameters: {
          model: @stt_model,
          file: audio_file,  # No need to transcode first, API should handle webm or mp4.
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

  def sanitize_tts_text(text)
    # Remove any code blocks
    text = text.gsub(/```.*?```/m, "")
    # Remove any HTML tags
    text = strip_tags(text)

    text
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
