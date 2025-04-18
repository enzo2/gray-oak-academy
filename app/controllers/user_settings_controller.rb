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
        format.turbo_stream { render :update, status: :unprocessable_entity }
      end
    end
  end

  def llm_models
    api_uri = params[:api_uri]
    Rails.logger.debug "API URI: #{api_uri}"
    if api_uri.present?
      normalized = api_uri.chomp("/")
      @models = Llm.where("api_provider = ? OR api_provider = ?", normalized, "#{normalized}/").pluck(:model)
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
    params.require(:setting).permit(:llm_model_name, :llm_api_access_token, :llm_api_base_uri)
  end
end
