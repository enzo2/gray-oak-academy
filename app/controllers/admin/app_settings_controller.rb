module Admin
  class AppSettingsController < Admin::BaseController
    before_action :require_superuser
    before_action :load_setting, only: [ :edit, :update ]

    def edit
      # Pre-fetch embedding models to populate cache for smoother validation
      Thread.new { AppSetting.fetch_openrouter_embedding_models }
    end

    def update
      if @setting.update(app_setting_params)
        redirect_to edit_admin_app_setting_path, notice: "App settings updated."
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
        :token_override,
        :image_llm_id,
        :embedding_model,
        :image_generation_two_pass,
        :user_daily_budget,
        :max_chat_cost,
        :openai_agent_model
      )
    end
  end
end
