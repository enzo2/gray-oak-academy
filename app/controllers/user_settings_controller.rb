class UserSettingsController < ApplicationController
  before_action :define_settings

  def update
    if @settings.update(user_settings_params)
      flash.now[:success] = "Settings updated successfully."
      respond_to do |format|
        format.turbo_stream
      end
    else
      flash.now[:error] = "Settings were not updated."
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_content }
      end
    end
  end

  # Returns a list of models for the given API URI to populate the combobox options
  def llm_models
    api_uri = params[:api_uri]
    Rails.logger.debug "API URI received: #{api_uri}"
    if api_uri.present?
      # Ensure the URI we query with has a trailing slash, matching the normalized Llm.api_provider
      normalized_uri_with_slash = api_uri.end_with?("/") ? api_uri : "#{api_uri}/"
      scope = Llm.where(api_provider: normalized_uri_with_slash)

      if params[:q].present?
        scope = scope.where("model ILIKE ?", "%#{params[:q]}%")
      end

      @models = scope.pluck(:model)
    else
      @models = []
    end
    Rails.logger.debug "Models: #{@models}"
    render turbo_stream: helpers.async_combobox_options(@models)
  end

  private

  def define_settings
    @settings = current_user.settings
  end

  def user_settings_params
    params.require(:setting).permit(
      :llm_model_name, :llm_api_access_token, :llm_api_base_uri,
      :reasoning_model_name,
      notification_preferences: {
        important: [ :email, :in_app ],
        student_progress: [ :email, :in_app ]
      }
    )
  end
end
