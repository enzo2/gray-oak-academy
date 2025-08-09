# Verifies a list of models against a SupportedApi by issuing a minimal completion per model.
# On success, a Completion is recorded which auto-creates/associates the Llm
class VerifySupportedApiModelsJob < ApplicationJob
  queue_as :default

  # Params:
  # - supported_api_id: Integer
  # - models: Array[String]
  # - enqueued_by_user_id: Integer (superuser/admin who initiated)
  def perform(supported_api_id:, models:, enqueued_by_user_id:)
    user = User.find(enqueued_by_user_id)
    return unless user.role_superuser?
    supported_api = SupportedApi.find(supported_api_id)
    unless supported_api.api_access_token.present?
      Rails.logger.info "SupportedApi #{supported_api.api_base_uri} cannot be verified because it has no api_access_token"
      return
    end

    # supported_api must have an api_access_token

    models.each do |model|
      begin
        # Minimal non-streaming call with explicit overrides so it doesn't rely on user settings
        service = OpenaiApiService.new(
          current_user: user,
          access_token: supported_api.api_access_token,
          base_uri: supported_api.api_base_uri,
          model: model,
        )

        # Lightweight verification prompt
        messages = [
          { role: "system", content: "This is a system test. A confirmation response is sought." },
          { role: "user", content: "Reply with a short confirmation message." }
        ]

        # A successful completion will create a Completion which will auto-create/find the Llm row
        service.complete(messages)

        Rails.logger.info "Verified model '#{model}' for SupportedApi #{supported_api.api_base_uri}"
      rescue StandardError => e
        Rails.logger.error "Failed to verify model '#{model}' for SupportedApi #{supported_api.api_base_uri}: #{e.message}"
        # Continue verifying remaining models
      end
    end
  end
end
