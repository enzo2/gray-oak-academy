class UserSettingsController < ApplicationController
  before_action :define_settings

  def update
    if @settings.update(user_settings_params)
      flash[:success] = "Settings updated successfully."
      respond_to do |format|
        format.turbo_stream { render :update }
      end
    else
      flash[:error] = "Settings were not updated."
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
      end
    end
  end

  private

  def define_settings
    @settings = current_user.settings
  end

  def user_settings_params
    params.require(:setting).permit(:llm_model_name, :llm_api_access_token, :llm_api_base_uri)
  end
end
