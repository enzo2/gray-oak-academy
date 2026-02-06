# Wrapper for OpenAI (or compatible) Speech API calls
class SpeechService
  require "faraday/retry" # needed?
  require "open3"
  require "tempfile"
  require "base64"
  include ActionView::Helpers::SanitizeHelper
  include OpenaiResponseHelper
  include OpenaiErrorHelper
  class SpeechServiceError < StandardError; end

  class << self
    attr_accessor :default_conn
  end

  def initialize(current_user:, conversation: nil)
    @user = current_user
    @conversation = conversation

    app_setting = AppSetting.settings
    unless app_setting
      raise SpeechServiceError, "Please ask the webmaster to configure App Settings."
    end

    # Resolve base URI and token for Speech API

    if AppSetting.speech_configured?
      @speech_base_uri = app_setting.provider_base_uri
      @speech_access_token = app_setting.effective_token

      @tts_model = app_setting.tts_model.presence
      @tts_voice = app_setting.tts_voice.presence
      @tts_instructions = app_setting.tts_instructions.presence || "Speak in a calm and friendly tone."

    end

    @stt_via = app_setting.stt_method # Should never be blank since default "speech" is initialized in db seeds

    # Determine chat STT model and base URI:
    if @stt_via == "chat" && app_setting.stt_model_id.present?
      llm = Llm.with_archived.find_by(id: app_setting.stt_model_id.to_i)
      if llm && !llm.archived?
        @stt_chat_model_name = llm.model
        @stt_chat_api_base_uri = llm.api_provider
      elsif llm&.archived?
        raise SpeechServiceError, "STT via LLM was set up, but the selected model is archived."
      else
        raise SpeechServiceError, "STT via LLM was set up, but selected stt_model_id #{app_setting.stt_model_id} not found."
      end
    else # using Speech API for STT
      @stt_model = app_setting.stt_model.presence
      # Client is only used for STT, since TTS uses Faraday directly for streaming
      @client = create_speech_client if @speech_base_uri && @speech_access_token
    end
  end

  # There is no point using an OpenAI API library for TTS, as the response time is so slow without chunked transfer encoding.
  # To stream the response to the user in realtime, we can:
  # 1) Use Faraday directly for streaming from the Speech API. Start processing chunks immediately.
  # 2) Send the chunks to ffmpeg to transmux to WebM/opus that the browser can stream with MSE (https://github.com/w3c/media-source/issues/245)
  # 3) Yield the audio chunks to the controller so they can be re-streamed using ActionController:Live.
  # 4) The Stimulus controller plays the stream as soon as it starts receiving chunks.
  def tts_stream(text, connection: nil, &block)
    unless @speech_base_uri && @speech_access_token && @tts_model && @tts_voice
      raise SpeechServiceError, "Speech API is not configured. Please ask the webmaster to configure App Settings."
    end
    text = sanitize_tts_text(text) # in case wasn't done yet
    return if text.blank?

    conn = connection || self.class.default_conn
    conn ||= Faraday.new(url: @speech_base_uri) do |faraday|
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
        data_streamed = false
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
            data_streamed = true

            begin
              ffmpeg_stdin.write(chunk)
            rescue Errno::EPIPE
              Rails.logger.debug "ffmpeg stdin pipe closed prematurely."
            end
          end
        end

        # If adapter didn't stream via on_data, write response.body now (e.g., Faraday::Adapter::Test)
        unless @client_disconnected || ffmpeg_stdin.closed? || data_streamed
          body = response.body
          if body.respond_to?(:read)
            while (c = body.read(8192))
              ffmpeg_stdin.write(c)
            end
          elsif body.respond_to?(:each)
            body.each { |c| ffmpeg_stdin.write(c) }
          elsif body
            ffmpeg_stdin.write(body.to_s)
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
  # Accepts a file
  def transcribe(audio_file)
    if @stt_via == "chat" && @stt_chat_api_base_uri.present? && @stt_chat_model_name.present?
      # Use LLM-based chat STT via shared helper
      transcribe_with_llm(audio_file: audio_file,
                          base_uri: @stt_chat_api_base_uri,
                          model: @stt_chat_model_name,
                          context: "Chat STT")
    elsif @stt_via != "chat" && @client && @stt_model.present?
      transcribe_via_speech_api(audio_file)
    elsif @conversation&.audio_input_permitted?
      # If STT is not configured, we can still fall back to the current conversation's LLM if it supports audio input.
      Rails.logger.warn "STT not configured, falling back to conversation's audio LLM for transcription."
      transcribe_with_llm(audio_file: audio_file,
                          base_uri: @conversation.llm_in_use.api_provider,
                          model: @conversation.llm_in_use.model,
                          context: "conversation LLM")
    else
      raise SpeechServiceError, "STT is not configured and no fallback audio LLM is available."
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
    OpenAI::Client.new(
      api_key: @speech_access_token,
      base_url: ensure_trailing_slash(@speech_base_uri),
      max_retries: 2,
      timeout: 60
    )
  end

  # Utility helpers for STT

  def ensure_trailing_slash(url)
    return url if url.blank? || url.end_with?("/")
    "#{url}/"
  end

  # Resolve token for an OpenAI-compatible Chat provider (LLM-based transcription)
  def resolve_llm_access_token(base_uri)
    # Try a shared SupportedApi token that matches the selected base URI
    provider = SupportedApi.selectable_for_teachers.find_by(api_base_uri: base_uri)
    return provider.api_access_token if provider&.api_access_token.present?

    # Fallback to ENV only if base URI matches
    env_base = ensure_trailing_slash(ENV["OPENAI_API_BASE_URL"])
    if ENV["OPENAI_API_KEY"].present? && env_base.present? && base_uri.present? && (env_base == base_uri)
      return ENV["OPENAI_API_KEY"]
    end

    raise SpeechServiceError, "No access token available for Chat STT provider (#{base_uri})."
  end

  # Convert any input file to 24kHz mono wav and return Base64 string (delegates to AudioConverter)
  def convert_file_to_base64_wav(input_path)
    AudioConverter.convert_to_base64_wav(input_path)
  end

  # STT via the Speech API (legacy / OpenAI Speech API-compatible route)
  def transcribe_via_speech_api(audio_file)
    begin
      response = @client.audio.transcriptions.create(
        model: @stt_model,
        file: audio_file,  # No need to transcode first, API should handle webm or mp4.
        response_format: "text"
      )
      text = extract_transcription_text(response)
      if text.blank?
        raise SpeechServiceError, "Empty transcription result from Speech API."
      end
      text
    rescue OpenAI::Errors::BadRequestError, OpenAI::Errors::UnprocessableEntityError, OpenAI::Errors::ConflictError => e
      error_message = extract_openai_error_message(e)
      Rails.logger.error "BadRequestError in STT transcription (Speech API): #{e.message}: #{error_message}"
      raise SpeechServiceError, "Bad Request: #{e.message}: #{error_message}"
    rescue OpenAI::Errors::AuthenticationError, OpenAI::Errors::PermissionDeniedError => e
      error_message = extract_openai_error_message(e)
      Rails.logger.error "Auth error in STT transcription (Speech API): #{e.message}: #{error_message}"
      raise SpeechServiceError, "Access key was unauthorized for STT transcription: #{error_message}"
    rescue OpenAI::Errors::NotFoundError => e
      error_message = extract_openai_error_message(e)
      Rails.logger.error "NotFoundError in STT transcription (Speech API): #{e.message}: #{error_message}"
      raise SpeechServiceError, "Resource not found: #{e.message}: #{error_message}"
    rescue OpenAI::Errors::RateLimitError => e
      error_message = extract_openai_error_message(e)
      Rails.logger.error "RateLimitError in STT transcription (Speech API): #{e.message}: #{error_message}"
      raise SpeechServiceError, "Too many requests for STT transcription: #{error_message}"
    rescue OpenAI::Errors::APITimeoutError => e
      Rails.logger.error "APITimeoutError in STT transcription (Speech API): #{e.message}"
      raise SpeechServiceError, "Speech API did not respond in time for STT."
    rescue OpenAI::Errors::APIConnectionError => e
      Rails.logger.error "APIConnectionError in STT transcription (Speech API): #{e.message}"
      raise SpeechServiceError, "The connection to the Speech API failed. Please try again."
    rescue OpenAI::Errors::ConversionError => e
      error_message = extract_openai_error_message(e)
      Rails.logger.error "ConversionError in STT transcription (Speech API): #{e.message}: #{error_message}"
      raise SpeechServiceError, "The client encountered an error. Details: #{error_message}"
    rescue OpenAI::Errors::InternalServerError, OpenAI::Errors::APIStatusError => e
      error_message = extract_openai_error_message(e)
      Rails.logger.error "APIStatusError in STT transcription (Speech API): #{e.message}: #{error_message}"
      raise SpeechServiceError, "Server Error: #{e.message}: #{error_message}"
    rescue OpenAI::Errors::APIError => e
      error_message = extract_openai_error_message(e)
      Rails.logger.error "APIError in STT transcription (Speech API): #{e.message}: #{error_message}"
      raise SpeechServiceError, "Server Error: #{e.message}: #{error_message}"
    rescue StandardError => e
      Rails.logger.error "StandardError in STT transcription (Speech API): #{e.message}"
      raise e
    end
  end

  def extract_transcription_text(response)
    return response if response.is_a?(String)
    return response.text if response.respond_to?(:text)

    response_hash = normalize_response_hash(response)
    return response_hash["text"] if response_hash.is_a?(Hash)

    nil
  end

  # Shared helper to transcribe audio using an LLM/chat completion provider.
  def transcribe_with_llm(base_uri:, model:, audio_file:, context: nil)
    token = resolve_llm_access_token(base_uri)

    audio_b64 = convert_file_to_base64_wav(audio_file.path)
    if audio_b64.blank?
      raise SpeechServiceError, "Failed to process audio for #{context || ''} transcription."
    end

    messages = [
      { role: "system", content: "Transcribe the audio. Output only the transcript. Don't include timestamps or other metadata; only the human-readable transcript." },
      { role: "user", content: [ { type: "input_audio", input_audio: { data: audio_b64, format: "wav" } } ] }
    ]

    begin
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: token,
        base_uri: base_uri,
        model: model,
        log_completion: false # Completion logging is only set up for LLMs.
      )

      text = service.complete(messages, temperature: 0).to_s
      if text.blank?
        raise SpeechServiceError, "Empty transcription result from #{context || 'LLM'}."
      end
      text
    rescue OpenAiError => e
      Rails.logger.error "OpenAiError in #{context || 'LLM'} transcription: #{e.message}"
      raise SpeechServiceError, e.message
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
