class MessagesController < ApplicationController
  include ActionView::RecordIdentifier

  def create
    @message = Message.new(message_params.except(:images_data).merge(conversation_id: params[:conversation_id], role: "user"))

    # Handle images
    if params[:message][:images_data].present?
      images_data = JSON.parse(params[:message][:images_data])
      images_data.each do |image_data|
        unless [ "image/png", "image/jpeg", "image/webp" ].include?(image_data["type"])
          raise StandardError, "Invalid image type. Only PNG, JPEG, and WebP are allowed."
        end

        if image_data["url"].present?
          # Handle URL-based images
          @message.images.build(uri: image_data["url"], content_type: image_data["type"])
        else
          # Handle file-based images (uploaded or pasted)
          data = image_data["data"].split(",")[1]
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(Base64.decode64(data)),
            filename: image_data["name"] || "pasted-image-#{Time.current.to_i}.#{image_data['type'].split('/')[1]}",
            content_type: image_data["type"]
          )
          @message.images.build(file: blob, content_type: image_data["type"])
        end
      end
    end

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
    unless conversation.audio_permitted?
      render json: { error: "Audio messages are not permitted for this conversation" }, status: :forbidden
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

    if @message.save # This will broadcast user message
      render :create  # Render the turbo_stream view to show a placeholder for the assistant reply
      GetLlmCompletionJob.perform_later(conversation: conversation) # Enqueue the job to process the audio message
    else
      @message.destroy
      render json: { error: "Failed to save audio", details: audio.errors.full_messages }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "Failed to create audio message: #{e.message}"
    # Attempt to destroy the potentially created message if an error occurred after its creation
    @message&.destroy
    render json: { error: "Failed to process audio message", details: e.message }, status: :internal_server_error
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

  # GET /messages/:id/tts
  def tts
    message = Message.find(params[:id])

    # Ensure it's an assistant message and has content
    unless message.role_assistant? && message.content.present?
      return head :not_found
    end

    # Ensure the user has access to this message's conversation
    unless message.conversation.user == current_user || current_user.role_admin?
      return head :forbidden
    end

    # Check if speech is configured for the user
    unless current_user.settings.speech_configured?
      Rails.logger.warn "Speech generation requested but not configured for user #{current_user.id}"
      return head :not_implemented
    end

    begin
      # Initialize the SpeechService
      speech_service = SpeechService.new(current_user: current_user)

      # Get the audio data using the new service (requests "opus" format, which openAI wraps in OGG)
      audio_data = speech_service.tts(message.content)

      # Send the audio data with the correct content type
      send_data audio_data, type: "audio/ogg", disposition: "inline"
    rescue SpeechService::SpeechServiceError => e # Catch specific service error
      Rails.logger.error "Speech generation failed for message #{message.id}: #{e.message}"
      # Return appropriate status based on error (e.g., 503 if API unavailable, 400 for bad request)
      # For simplicity, returning 500 for now. Consider more specific error codes.
      status_code = case e.message
      when /unauthorized/i
                      :unauthorized
      when /Bad Request/i
                      :bad_request
      when /not configured/i
                      :not_implemented
      else
                      :internal_server_error
      end
      head status_code
    rescue StandardError => e
      Rails.logger.error "Unexpected error during speech generation for message #{message.id}: #{e.message}"
      head :internal_server_error
    end
  end

  private

  def message_params
    params.require(:message).except(:images).permit(:content, :images_data)
  end
end
