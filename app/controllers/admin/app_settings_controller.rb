module Admin
  class AppSettingsController < Admin::BaseController
    before_action :require_superuser
    before_action :load_setting, only: [ :edit, :update ]

    def edit
    end

    def update
      if @setting.update(app_setting_params)
        redirect_to admin_app_setting_path, notice: "App settings updated."
      else
        flash.now[:error] = "Failed to update app settings."
        render :edit, status: :unprocessable_content
      end
    end

    private

    def load_setting
      if app_setting = AppSetting.settings
        @setting = app_setting
      else
        raise ActiveRecord::RecordNotFound, "AppSetting not found. Please run db seeds."
      end
    end

    def app_setting_params
      params.require(:app_setting).permit(
        :provider_supported_api_id,
        :stt_method,
        :stt_model,
        :stt_model_id,
        :tts_model,
        :tts_voice,
        :tts_instructions,
        :token_override
      )
    end
  end
end
