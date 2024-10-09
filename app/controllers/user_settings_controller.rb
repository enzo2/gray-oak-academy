class UserSettingsController < ApplicationController
  before_action :authenticate_user!

  def update
    if current_user.settings.update(user_settings_params)
      redirect_to edit_user_registration_path, notice: 'Settings updated successfully.'
    else
      redirect_to edit_user_registration_path, alert: 'Failed to update settings.'
    end
  end

  private

  def user_settings_params
    params.require(:user).permit(settings: {})
  end
end
