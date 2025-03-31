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
    GetLlmCompletionJob.perform_later(conversation_id: @message.conversation_id)

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

  private

  def message_params
    params.require(:message).except(:images).permit(:content, :images_data)
  end
end
