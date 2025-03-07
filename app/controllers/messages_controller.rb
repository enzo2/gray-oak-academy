class MessagesController < ApplicationController
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
          @message.images.build(
            uri: image_data["url"],
            content_type: image_data["type"]
          )
        else
          # Handle file-based images (uploaded or pasted)
          data = image_data["data"].split(",")[1]
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(Base64.decode64(data)),
            filename: image_data["name"] || "pasted-image-#{Time.current.to_i}.#{image_data['type'].split('/')[1]}",
            content_type: image_data["type"]
          )
          @message.images.build(
            file: blob,
            content_type: image_data["type"]
          )
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
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    request = Net::HTTP::Head.new(uri.request_uri)
    response = http.request(request)
    Rails.logger.info "Proxying image: #{url}"
    Rails.logger.info "Response code: #{response.code}"
    Rails.logger.info "Response content-type: #{response["Content-Type"]}"
    render plain: "", status: response.code, content_type: response["Content-Type"]
  end

  private

  def message_params
    params.require(:message).except(:images).permit(:content, :images_data)
  end
end
