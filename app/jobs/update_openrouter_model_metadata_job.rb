class UpdateOpenrouterModelMetadataJob < ApplicationJob
  queue_as :default

  require "net/http"
  require "uri"

  def perform(llms = nil)
    if llms.nil?
      update_all_models
      return
    end

    Array.wrap(llms).compact.each do |llm|
      update_metadata(llm)
    end
  end

  private

  def fetch_model_endpoints(llm)
    url = "https://openrouter.ai/api/v1/models/#{llm.model}/endpoints"
    Rails.logger.debug("Fetching model endpoints from #{url}")
    HttpJsonService.get(url)
  end

  def update_metadata(llm)
    return unless llm.api_provider.include?("openrouter.ai")
    response = fetch_model_endpoints(llm)
    return nil unless response && response["data"] && response["data"]["endpoints"]

    # Get the minimum context length across all endpoints
    context_length = response["data"]["endpoints"].map { |e| e["context_length"] }.compact.min

    # Get the supported_parameters
    parameter_arrays = response["data"]["endpoints"].map { |e| e["supported_parameters"] }
    input_modalities = response["data"]["architecture"]["input_modalities"] || nil
    output_modalities = response["data"]["architecture"]["output_modalities"] || nil

    # Find the intersection of all the arrays
    common_parameters = parameter_arrays.reduce(:&)

    llm.update!(
      context_length: context_length,
      supported_parameters: common_parameters || [],
      supports_audio_input: input_modalities&.include?("audio"),
      supports_image_input: input_modalities&.include?("image"),
      supports_audio_output: output_modalities&.include?("audio"),
      supports_image_output: output_modalities&.include?("image"),
      metadata_fetched_at: Time.current
    )
    Rails.logger.info("Updated metadata for #{llm.model}")
  rescue StandardError => e
    Rails.logger.error("Error updating metadata for #{llm.model}: #{e.message}")
  end

  def update_all_models
    Llm.where("api_provider LIKE ?", "%openrouter.ai%").find_each do |llm|
      update_metadata(llm)
    end
  end
end
