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

  def fetch_image_model_endpoints(llm)
    openrouter = SupportedApi.find_by(api_base_uri: SupportedApi::OPENROUTER_BASE_URI)
    token = openrouter&.api_access_token
    return nil if token.blank?

    url = "#{SupportedApi::OPENROUTER_BASE_URI}images/models/#{llm.model}/endpoints"
    Rails.logger.debug("Fetching image model endpoints from #{url}")
    HttpJsonService.get(url, headers: { "Authorization" => "Bearer #{token}" })
  end

  def update_metadata(llm)
    return unless llm.api_provider.include?("openrouter.ai")
    return if update_image_metadata(llm)

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

  def update_image_metadata(llm)
    image_model = AppSetting.fetch_openrouter_image_model_data.find { |model| model["id"] == llm.model }
    return false unless image_model

    endpoints_response = fetch_image_model_endpoints(llm)
    endpoints = Array(endpoints_response&.dig("endpoints"))
    parameter_sets = endpoints.filter_map { |endpoint| supported_parameter_names(endpoint["supported_parameters"]) }
    parameter_sets = [ supported_parameter_names(image_model["supported_parameters"]) ].compact if parameter_sets.blank?
    common_parameters = parameter_sets.reduce(:&) || []
    architecture = image_model["architecture"] || {}
    input_modalities = architecture["input_modalities"] || []
    output_modalities = architecture["output_modalities"] || []

    llm.update!(
      supported_parameters: common_parameters,
      supports_audio_input: input_modalities.include?("audio"),
      supports_image_input: input_modalities.include?("image"),
      supports_audio_output: output_modalities.include?("audio"),
      supports_image_output: output_modalities.include?("image"),
      metadata_fetched_at: Time.current
    )
    Rails.logger.info("Updated image metadata for #{llm.model}")
    true
  end

  def supported_parameter_names(value)
    case value
    when Hash
      value.keys
    when Array
      value.map(&:to_s)
    end
  end

  def update_all_models
    Llm.where("api_provider LIKE ?", "%openrouter.ai%").find_each do |llm|
      update_metadata(llm)
    end
  end
end
