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

    # Returns TTS/STT model options for the selected speech provider.
    def speech_models
      api_uri = SupportedApi.normalize_base_uri(params[:api_uri])
      kind = params[:kind].to_s
      @models = []

      if api_uri == SupportedApi::OPENROUTER_BASE_URI
        @models = case kind
        when "tts"
          AppSetting.fetch_openrouter_tts_models
        when "stt"
          AppSetting.fetch_openrouter_stt_models
        else
          []
        end
        @models = @models.select { |model| model.downcase.include?(params[:q].to_s.downcase) } if params[:q].present?
      end

      render turbo_stream: helpers.async_combobox_options(@models)
    end

    def speech_voices
      api_uri = SupportedApi.normalize_base_uri(params[:api_uri])
      @voices = []

      if api_uri == SupportedApi::OPENROUTER_BASE_URI
        @voices = AppSetting.fetch_openrouter_tts_voices(model: params[:model].to_s)
        @voices = @voices.select { |voice| voice.downcase.include?(params[:q].to_s.downcase) } if params[:q].present?
      end

      render turbo_stream: helpers.async_combobox_options(@voices)
    end

    def background_agent_model_status
      provider = SupportedApi.find_responses_agent_selectable_by_id(params[:provider_id])
      api_uri = provider&.api_base_uri.to_s
      model = params[:model].to_s.strip
      context_length = nil

      if api_uri == SupportedApi::OPENROUTER_BASE_URI && model.present?
        context_length = Llm.find_by(
          api_provider: SupportedApi.normalize_base_uri(api_uri),
          model: model
        )&.context_length
      end

      render json: {
        provider_key_present: provider&.api_access_token.present? || false,
        openrouter: api_uri == SupportedApi::OPENROUTER_BASE_URI,
        model_present: model.present?,
        context_length: context_length
      }
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
      permitted_attributes = [
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
        :background_agent_supported_api_id,
        :background_agent_model,
        :background_agent_prefer_user_codex,
        :background_agent_codex_model,
        :background_agent_max_tool_turns,
        :exa_api_key,
        :exa_research_model
      ]
      permitted_attributes << :course_outline_research_stub_enabled if Rails.env.development?

      permitted = params.require(:app_setting).permit(*permitted_attributes)
      scrub_masked_secret_params!(permitted)
      permitted
    end

    def scrub_masked_secret_params!(permitted)
      [ :token_override, :exa_api_key ].each do |field|
        if permitted[field] == AppSetting::MASKED_SECRET_VALUE
          permitted.delete(field)
          next
        end

        permitted[field] = nil if permitted[field].blank?
      end
    end
  end
end
