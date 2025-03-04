class UpdateOpenrouterModelMetadataJob < ApplicationJob
  queue_as :default

  require "net/http"
  require "uri"

  def perform(llm = nil)
    if llm
      update_metadata(llm)
    else
      update_all_models
    end
  end

  private

  def fetch_model_endpoints(llm)
    url = "https://openrouter.ai/api/v1/models/#{llm.model}/endpoints"
    Rails.logger.debug("Fetching model endpoints from #{url}")
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Error fetching model endpoints: #{e.message}")
    nil
  end

  def update_metadata(llm)
    response = fetch_model_endpoints(llm)
    return nil unless response && response["data"] && response["data"]["endpoints"]

    # Get the minimum context length across all endpoints
    context_length = response["data"]["endpoints"].map { |e| e["context_length"] }.compact.min

    # Get the supported_parameters
    parameter_arrays = response["data"]["endpoints"].map { |e| e["supported_parameters"] }
    # Find the intersection of all the arrays
    common_parameters = parameter_arrays.reduce(:&)

    llm.update!(
      context_length: context_length,
      supported_parameters: common_parameters || [],
      metadata_fetched_at: Time.current
    )
    Rails.logger.info("Updated metadata for #{llm.model}")
  rescue StandardError => e
    Rails.logger.error("Error updating metadata for #{llm.model}: #{e.message}")
  end

  def update_all_models
    Llm.where(api_provider: "OpenRouter").find_each do |llm|
      update_metadata(llm)
    end
  end
end
