class MessagesController < ApplicationController
  include ActionView::RecordIdentifier
  include ActionController::Live

  def create
    @message = Message.new(message_params.except(:images_data).merge(conversation_id: params[:conversation_id], role: "user"))

    # Handle images
    process_images_param(@message, params[:message][:images_data]) if params[:message][:images_data].present?

    # This will trigger the model callback to broadcast the user message synchronously, before the turbo_stream view below is rendered.
    @message.save!

    # Get completion and stream the response to the conversation view
    GetLlmCompletionJob.perform_later(conversation: @message.conversation)

    # The view is then rendered with a placeholder for the assistant message while the above job runs.
    respond_to do |format|
      format.turbo_stream
    end
  rescue StandardError => e
    Rails.logger.error "Failed to create message: #{e.message}"
    render turbo_stream: turbo_stream.replace(
      "#{dom_id(@message.conversation)}_message_form",
      partial: "messages/form",
      locals: { conversation: @message.conversation, error: e.message }
    ), status: :unprocessable_entity
  end


  # POST /conversations/:conversation_id/audio_messages
  def create_audio_message
    conversation = Conversation.find(params[:conversation_id])
    unless conversation.audio_input_permitted?
      render json: {
        error: "Audio messages are not permitted for this conversation. Use transcription instead."
        }, status: :forbidden
      return
    end

    audio_file = params[:audio]
    unless audio_file
      render json: { error: "No audio file provided" }, status: :bad_request
      return
    end

    # Create new user message with audio attachment
    @message = conversation.messages.new(role: "user", content: "") # Content is empty for audio-only messages
    audio = @message.audios.build(content_type: audio_file.content_type)
    audio.file.attach(audio_file)

    # Handle images if present
    process_images_param(@message, params[:images_data]) if params[:images_data].present?

    if @message.save # This will broadcast user message
      respond_to do |format|
        format.turbo_stream { render :create } # Render the turbo_stream view to show a placeholder for the assistant reply
      end
      GetLlmCompletionJob.perform_later(conversation: conversation) # Enqueue the job to process the audio message
    else
      @message.destroy
      render json: { error: "Failed to save audio", details: audio.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    # Attempt to destroy the potentially created message if an error occurred after its creation
    @message&.destroy
    Rails.logger.error "Failed to create audio message: #{e.message}"
    broadcast_flash(conversation, "Failed to create audio message: #{e.message}")
    render json: { error: "Failed to process audio message", details: e.message }, status: :internal_server_error
  end

  # POST /conversations/:conversation_id/transcribed_messages
  def create_transcribed_message
    conversation = Conversation.find(params[:conversation_id])
    unless params[:audio]
      render json: { error: "No audio file provided" }, status: :bad_request
      return
    end

    # Create a new user message with empty content. Will be broadcast to the conversation view.
    @message = conversation.messages.create!(role: "user", content: "")

    # Handle images if present
    process_images_param(@message, params[:images_data]) if params[:images_data].present?

    # Run STT using SpeechService
    begin
      speech_service = SpeechService.new(current_user: current_user)
      transcription = speech_service.transcribe(params[:audio].tempfile)
      @message.content = transcription
      if @message.save # This will broadcast the updated message
        respond_to do |format|
          format.turbo_stream { render :create } # Render the turbo_stream view to show a placeholder for the assistant reply
        end
        # Enqueue the completion once we are sure the user message has been transcribed and saved
        GetLlmCompletionJob.perform_later(conversation: conversation)
      else
        @message.destroy
        broadcast_flash(conversation, "Failed to save message: #{@message.errors.full_messages.join(', ')}")
        Rails.logger.error "Failed to save message: #{@message.errors.full_messages.join(', ')}"
        render json: { error: "Failed to save message", details: @message.errors.full_messages }, status: :unprocessable_entity
      end
    rescue SpeechService::SpeechServiceError => e
      @message.destroy
      Rails.logger.error "STT failed: #{e.message}"
      broadcast_flash(conversation, "Transcription failed: #{e.message}")
      render json: { error: "Transcription failed", details: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      @message.destroy
      Rails.logger.error "Unexpected error during STT: #{e.message}"
      broadcast_flash(conversation, "An unexpected error occurred: #{e.message}")
      render json: { error: "An unexpected error occurred", details: e.message }, status: :internal_server_error
    end
  end

  # Proxy the image content-type check, since it can't be done in the Stimulus controller due to CORS
  def proxy_image
    require "net/http"
    require "uri"
    url = params[:url]

    # Validate URL
    uri = URI.parse(url)
    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return head :forbidden
    end

    # Block internal network requests
    ip = Addrinfo.ip(uri.host)
    if ip.ipv4_private? || ip.ipv4_loopback? ||
       IPAddr.new("fc00::/7").include?(ip.ip_address) || # ULA
       IPAddr.new("::1").include?(ip.ip_address)         # IPv6 loopback
      return head :forbidden
    end

    # Set up HTTP client with timeouts
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 5  # seconds
    http.read_timeout = 10 # seconds

    request = Net::HTTP::Head.new(uri.request_uri)
    response = http.request(request)
    Rails.logger.debug "Proxying image: #{url}"
    Rails.logger.debug "Response code: #{response.code}"
    Rails.logger.debug "Response content-type: #{response["Content-Type"]}"

    # Only allow images under 10MB
    if response["Content-Length"].to_i > 10.megabytes
      return head :request_entity_too_large
    end

    # Only allow specific content types
    unless [ "image/png", "image/jpeg", "image/webp" ].include?(response["Content-Type"].to_s.split(";").first)
      return head :forbidden
    end

    render plain: "", status: response.code, content_type: response["Content-Type"]
  rescue StandardError => e
    Rails.logger.error "Image proxy error: #{e.message}"
    head :bad_request
  end

  # GET /messages/:id/tts_stream
  def tts_stream
    message = Message.find(params[:id])

    unless message.role_assistant? && message.content.present?
      return head :not_found
    end

    unless message.conversation.user == current_user || current_user.role_admin?
      return head :forbidden
    end

    unless current_user.settings.speech_configured?
      Rails.logger.warn "Streaming speech requested but not configured for user #{current_user.id}"
      return head :not_implemented
    end

    # Set headers for streaming
    response.headers["Content-Type"] = "audio/webm" # SpeechService transmuxes to webm
    response.headers["Cache-Control"] = "no-cache" # Prevent caching
    response.headers.delete("ETag") # Disable Rack::ETag buffering
    response.headers.delete("Content-Length") # Required for streaming
    response.headers["Last-Modified"] = Time.now.httpdate # Helps prevent some middleware buffering

    # Use response.stream to send data as it arrives
    begin
      speech_service = SpeechService.new(current_user: current_user)
      speech_service.tts_stream(message.content) do |chunk|
        response.stream.write chunk
        # Rails.logger.debug "Sent chunk of size #{chunk.bytesize} for message #{message.id}"
      end
    rescue SpeechService::SpeechServiceError => e
      Rails.logger.error "Speech generation failed for message #{message.id}: #{e.message}"
      broadcast_flash(message.conversation, e.message)
      head :internal_server_error unless response.committed?
    rescue ActionController::Live::ClientDisconnected
      Rails.logger.info "Client disconnected during TTS stream for message #{message.id}"
    rescue StandardError => e
      Rails.logger.error "Unexpected error during TTS streaming for message #{message.id}: #{e.message}"
    ensure
      response.stream.close # Ensure the stream is closed
    end
  end

  private

  def message_params
    params.require(:message).except(:images).permit(:content, :images_data)
  end

  def broadcast_flash(conversation, error_msg)  # Update the flash bar
    Turbo::StreamsChannel.broadcast_update_later_to(
      "#{dom_id(conversation)}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: error_msg } }
    )
  end

  def process_images_param(message, images_data_param)
    images_data = JSON.parse(images_data_param)
    images_data.each do |image_data|
      unless [ "image/png", "image/jpeg", "image/webp" ].include?(image_data["type"])
        raise StandardError, "Invalid image type. Only PNG, JPEG, and WebP are allowed."
      end
      if image_data["url"].present?
        message.images.build(uri: image_data["url"], content_type: image_data["type"])
      else
        data = image_data["data"].split(",")[1]
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(Base64.decode64(data)),
          filename: image_data["name"] || "pasted-image-#{Time.current.to_i}.#{image_data['type'].split('/')[1]}",
          content_type: image_data["type"]
        )
        message.images.build(file: blob, content_type: image_data["type"])
      end
    end
  end
end
