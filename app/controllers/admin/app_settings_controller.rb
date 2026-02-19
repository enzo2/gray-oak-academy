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

    # Returns model options for the selected provider URI for async comboboxes.
    def llm_models
      api_uri = params[:api_uri].to_s
      @models = []

      if api_uri.present?
        normalized_api_uri = api_uri.end_with?("/") ? api_uri : "#{api_uri}/"
        scope = Llm.where(api_provider: normalized_api_uri)
        scope = scope.where("model ILIKE ?", "%#{params[:q]}%") if params[:q].present?
        @models = scope.pluck(:model)
      end

      render turbo_stream: helpers.async_combobox_options(@models)
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
      permitted = params.require(:app_setting).permit(
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
        :openai_agent_supported_api_id,
        :openai_agent_model,
        :openai_agent_max_tool_turns,
        :exa_api_key,
        :exa_research_model
      )
      scrub_masked_secret_params!(permitted)
      permitted
    end

    def scrub_masked_secret_params!(permitted)
      [ :token_override, :exa_api_key ].each do |field|
        next unless permitted[field] == AppSetting::MASKED_SECRET_VALUE

        permitted.delete(field)
      end
    end
  end
end
