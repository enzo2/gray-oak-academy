module Admin
  class LlmsController < Admin::BaseController
    before_action :require_superuser
    before_action :set_llm, only: :update

    def index
      @provider = params[:provider].presence
      @q = params[:q].presence

      scope = Llm.all
      scope = scope.where(api_provider: @provider) if @provider
      scope = scope.where("model ILIKE ?", "%#{@q}%") if @q
      @llms = scope.order(:api_provider, :model)

      @providers = Llm.order(:api_provider).distinct.pluck(:api_provider)
      @supported_uris = SupportedApi.pluck(:api_base_uri)
    end

    def update
      if @llm.update(llm_params)
        flash.now[:success] = "LLM updated."
      else
        flash.now[:error] = "Failed to update LLM."
      end
      respond_to do |format|
        format.turbo_stream  # This will display the flash message.
        format.html { redirect_back_or_to(fallback_location: admin_llms_path) }
      end
    end

    private

    def set_llm
      @llm = Llm.find(params[:id])
    end

    def llm_params
      params.require(:llm).permit(:supports_audio_input)
    end
  end
end
