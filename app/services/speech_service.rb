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
      @client = create_speech_client if @speech_base_uri && @speech_access_token && !openrouter_speech_provider?
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

    begin
      conn = connection || self.class.default_conn || create_speech_faraday_connection
      if openrouter_speech_provider?
        tts_stream_openrouter(text, conn, &block)
      else
        tts_stream_openai_compatible(text, conn, &block)
      end

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
    rescue Faraday::UnauthorizedError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::UnauthorizedError in TTS generation: #{e.message}: #{error_message}"
      raise SpeechServiceError, "Access key was unauthorized for TTS generation: #{error_message}"
    rescue Faraday::ClientError => e
      error_message = extract_faraday_error_message(e)
      Rails.logger.error "Faraday::ClientError in TTS generation: #{e.message} #{error_message}"
      raise SpeechServiceError, "#{e.message}: #{error_message}"
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
    elsif @stt_via != "chat" && @speech_base_uri && @speech_access_token && @stt_model.present?
      if openrouter_speech_provider?
        transcribe_via_openrouter_speech_api(audio_file)
      else
        transcribe_via_speech_api(audio_file)
      end
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
      timeout: OpenaiClientDefaults.timeout_seconds
    )
  end

  def create_speech_faraday_connection
    Faraday.new(url: @speech_base_uri) do |faraday|
      faraday.request :authorization, "Bearer", @speech_access_token
      faraday.request :retry, { max: 2, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }
      faraday.response :raise_error
      faraday.adapter Faraday.default_adapter
    end
  end

  def openrouter_speech_provider?
    URI.parse(ensure_trailing_slash(@speech_base_uri).to_s).host == "openrouter.ai"
  rescue URI::InvalidURIError
    false
  end

  def tts_stream_openai_compatible(text, conn, &block)
    payload = {
      model: @tts_model,
      input: text,
      voice: @tts_voice,
      response_format: "opus", # OpenAI returns Opus in an Ogg container.
      instructions: @tts_instructions
    }.to_json

    stream_tts_response(
      conn: conn,
      payload: payload,
      ffmpeg_command: [ "ffmpeg", "-i", "pipe:0", "-vn", "-c:a", "copy", "-f", "webm", "-nostdin", "-loglevel", "error", "pipe:1" ],
      &block
    )
  end

  def tts_stream_openrouter(text, conn, &block)
    @tts_audio_yielded = false
    stream_tts_response(
      conn: conn,
      payload: openrouter_tts_payload(text, response_format: "pcm"),
      ffmpeg_command: [ "ffmpeg", "-f", "s16le", "-ar", "24000", "-ac", "1", "-i", "pipe:0", "-vn", "-c:a", "libopus", "-f", "webm", "-nostdin", "-loglevel", "error", "pipe:1" ],
      delay_output_until_source_audio: true,
      &block
    )
  rescue Faraday::Error, SpeechServiceError => e
    raise if @tts_audio_yielded || @client_disconnected

    Rails.logger.warn "OpenRouter PCM TTS failed before audio streamed; retrying with mp3. #{e.class}: #{e.message}"
    stream_tts_response(
      conn: conn,
      payload: openrouter_tts_payload(text, response_format: "mp3"),
      ffmpeg_command: [ "ffmpeg", "-i", "pipe:0", "-vn", "-c:a", "libopus", "-f", "webm", "-nostdin", "-loglevel", "error", "pipe:1" ],
      &block
    )
  end

  def openrouter_tts_payload(text, response_format:)
    payload = {
      model: @tts_model,
      input: text,
      voice: @tts_voice,
      response_format: response_format
    }

    if @tts_instructions.present? && @tts_model.to_s.start_with?("openai/")
      payload[:provider] = { options: { openai: { instructions: @tts_instructions } } }
    end

    payload.to_json
  end

  def stream_tts_response(conn:, payload:, ffmpeg_command:, delay_output_until_source_audio: false, &block)
    ffmpeg_stderr_output = ""
    @client_disconnected = false
    output_mutex = Mutex.new
    source_audio_started = !delay_output_until_source_audio
    buffered_output = []

    emit_chunk = lambda do |chunk|
      chunks_to_emit = nil
      output_mutex.synchronize do
        if source_audio_started
          chunks_to_emit = [ chunk ]
        else
          buffered_output << chunk
          return
        end
      end

      chunks_to_emit.each do |chunk_to_emit|
        @tts_audio_yielded = true
        block.call(chunk_to_emit)
      end
    end

    mark_source_audio_started = lambda do
      chunks_to_emit = []
      output_mutex.synchronize do
        unless source_audio_started
          source_audio_started = true
          chunks_to_emit = buffered_output.dup
          buffered_output.clear
        end
      end

      chunks_to_emit.each do |chunk_to_emit|
        @tts_audio_yielded = true
        block.call(chunk_to_emit)
      end
    end

    Open3.popen3(*ffmpeg_command) do |ffmpeg_stdin, ffmpeg_stdout, ffmpeg_stderr, wait_thr|
      ffmpeg_stdin.binmode
      ffmpeg_stdout.binmode
      Rails.logger.info "SpeechService: Started ffmpeg process with PID #{wait_thr.pid}"

      stderr_thread = Thread.new do
        begin
          ffmpeg_stderr_output = ffmpeg_stderr.read
        rescue IOError => e
          Rails.logger.debug "IOError reading ffmpeg stderr (expected on close): #{e.message}"
        ensure
          ffmpeg_stderr.close
        end
      end
      stderr_thread.report_on_exception = false

      stdout_thread = Thread.new do
        begin
          while (chunk = ffmpeg_stdout.read(8192))
            begin
              emit_chunk.call(chunk)
            rescue ActionController::Live::ClientDisconnected
              @client_disconnected = true
              Rails.logger.info "Client disconnected during yield in SpeechService stdout_thread. Stopping stream."
              break
            end
          end
        rescue IOError => e
          Rails.logger.warn "IOError reading ffmpeg stdout (expected on close): #{e.message}"
        ensure
          ffmpeg_stdout.close unless ffmpeg_stdout.closed?
        end
      end
      stdout_thread.report_on_exception = false

      data_streamed = false
      response = nil
      begin
        response = conn.post("audio/speech") do |req|
          req.headers["Content-Type"] = "application/json"
          req.headers["Transfer-Encoding"] = "chunked"
          req.body = payload
          req.options.timeout = 120
          req.options.open_timeout = 10

          req.options.on_data = Proc.new do |chunk, _overall_received_bytes, response_env|
            next if @client_disconnected || ffmpeg_stdin.closed?
            next unless response_env&.success?
            next unless chunk.bytesize.positive?

            data_streamed = true

            begin
              mark_source_audio_started.call
              ffmpeg_stdin.write(chunk)
            rescue ActionController::Live::ClientDisconnected
              @client_disconnected = true
            rescue Errno::EPIPE
              Rails.logger.debug "ffmpeg stdin pipe closed prematurely."
            end
          end
        end

        unless @client_disconnected || ffmpeg_stdin.closed? || data_streamed
          source_audio_written = write_response_body_to_io(response.body, ffmpeg_stdin)
          begin
            mark_source_audio_started.call if source_audio_written
          rescue ActionController::Live::ClientDisconnected
            @client_disconnected = true
          end
        end
      ensure
        ffmpeg_stdin.close unless ffmpeg_stdin.closed?
        stdout_thread.join
        stderr_thread.join
      end

      ffmpeg_status = wait_thr.value
      Rails.logger.info "ffmpeg process and reader threads finished"

      unless ffmpeg_status.success? || @client_disconnected
        Rails.logger.error "ffmpeg failed with status: #{ffmpeg_status.exitstatus}. Stderr: #{ffmpeg_stderr_output}"
        raise SpeechServiceError, "Audio processing failed (ffmpeg exited with status #{ffmpeg_status.exitstatus}). Error: #{ffmpeg_stderr_output.lines.last || 'Unknown ffmpeg error'}"
      end

      Rails.logger.info "ffmpeg completed successfully"

      unless response.success?
        Rails.logger.error "TTS API request failed post-stream with status #{response.status}"
        Rails.logger.error "Error details: #{response.body}" if response.body.present?
        raise SpeechServiceError, "TTS API request failed with status #{response.status}" unless ffmpeg_status.success?
      end

      # A 200 with an empty body produces no audio. Surface it as an error so
      # callers (e.g. OpenRouter PCM) can fall back instead of silently
      # returning no sound.
      if response.success? && ffmpeg_status.success? && !@tts_audio_yielded && !@client_disconnected
        raise SpeechServiceError, "TTS API returned a successful response but produced no audio"
      end
    end
  end

  def write_response_body_to_io(body, io)
    wrote_data = false
    if body.respond_to?(:read)
      while (chunk = body.read(8192))
        io.write(chunk)
        wrote_data ||= chunk.bytesize.positive?
      end
    elsif body.respond_to?(:each)
      body.each do |chunk|
        io.write(chunk)
        wrote_data ||= chunk.bytesize.positive?
      end
    elsif body
      io.write(body.to_s)
      wrote_data ||= body.to_s.bytesize.positive?
    end
    wrote_data
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

  # STT via the Speech API (OpenAI Speech API-compatible route)
  def transcribe_via_speech_api(audio_file)
    begin
      upload_file = normalize_stt_upload_file(audio_file)
      response = create_speech_transcription_response(upload_file: upload_file)
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

  def transcribe_via_openrouter_speech_api(audio_file)
    upload_file = normalize_stt_upload_file(audio_file)
    audio_path = upload_file.respond_to?(:path) ? upload_file.path : upload_file.to_s
    audio_b64 = convert_file_to_base64_wav(audio_path)
    if audio_b64.blank?
      raise SpeechServiceError, "Failed to process audio for OpenRouter transcription."
    end

    response = create_openrouter_transcription_response(audio_b64)
    text = extract_openrouter_transcription_text(response.body)
    if text.blank?
      raise SpeechServiceError, "Empty transcription result from OpenRouter Speech API."
    end
    text
  rescue Faraday::Error => e
    error_message = extract_faraday_error_message(e)
    Rails.logger.error "Faraday error in OpenRouter STT transcription: #{e.message}: #{error_message}"
    raise SpeechServiceError, "OpenRouter STT request failed: #{error_message}"
  end

  def create_speech_transcription_response(upload_file:)
    @client.audio.transcriptions.create(
      model: @stt_model,
      file: upload_file, # No need to transcode first, API should handle webm or mp4.
      response_format: "text"
    )
  rescue TypeError, OpenAI::Errors::ConversionError => e
    Rails.logger.warn "Speech API transcription response parse failed in SDK (#{e.class}): #{e.message}. Falling back to raw response."
    @client.request(
      method: :post,
      path: "audio/transcriptions",
      headers: { "content-type" => "multipart/form-data" },
      body: {
        model: @stt_model,
        file: upload_file,
        response_format: "text"
      }
    )
  end

  def create_openrouter_transcription_response(audio_b64)
    conn = self.class.default_conn || create_speech_faraday_connection
    conn.post("audio/transcriptions") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = {
        model: @stt_model,
        input_audio: {
          data: audio_b64,
          format: "wav"
        }
      }.to_json
      req.options.timeout = 120
      req.options.open_timeout = 10
    end
  end

  # OpenAI SDK treats String file inputs as in-memory text payloads, not filesystem paths.
  # Normalize inputs to a true file upload type so multipart `file` is always a file part.
  def normalize_stt_upload_file(audio_file)
    file = if audio_file.respond_to?(:tempfile)
      audio_file.tempfile
    else
      audio_file
    end

    if file.is_a?(String)
      path = Pathname.new(file)
      unless path.exist?
        raise SpeechServiceError, "Audio file path does not exist: #{file}"
      end
      return path
    end

    if file.respond_to?(:path) && file.path.present?
      path = Pathname.new(file.path)
      return path if path.exist?
    end

    file.rewind if file.respond_to?(:rewind)
    file
  end

  def extract_transcription_text(response)
    return response if response.is_a?(String)

    if response.respond_to?(:read)
      response.rewind if response.respond_to?(:rewind)
      text = response.read.to_s
      response.rewind if response.respond_to?(:rewind)
      return text
    end

    return response.text if response.respond_to?(:text)

    response_hash = normalize_response_hash(response)
    return response_hash["text"] if response_hash.is_a?(Hash)

    nil
  end

  def extract_openrouter_transcription_text(body)
    parsed = if body.is_a?(String)
      begin
        JSON.parse(body)
      rescue JSON::ParserError
        return body
      end
    else
      normalize_response_hash(body)
    end

    parsed = normalize_response_hash(parsed)
    parsed["text"]
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
    response = exception.respond_to?(:response) ? exception.response : nil
    response_body = response.is_a?(Hash) ? (response[:body] || response["body"]) : nil
    status = response.is_a?(Hash) ? (response[:status] || response["status"]) : nil

    if response_body.blank?
      return "Unauthorized (no error body returned by provider)." if status.to_i == 401
      return exception.message
    end

    Rails.logger.error "Error response body: #{response_body}"

    parsed = if response_body.is_a?(String)
      begin
        JSON.parse(response_body)
      rescue JSON::ParserError
        return response_body
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
    elsif parsed.is_a?(Hash) && parsed["error"].is_a?(String)
      parsed["error"]
    else
      parsed.to_s
    end
  end
end
