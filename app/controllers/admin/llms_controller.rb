module Admin
  class LlmsController < Admin::BaseController
    before_action :require_superuser
    before_action :set_llm, only: %i[update archive unarchive]

    def index
      @provider = params[:provider].presence
      @q = params[:q].presence
      @show_archived = params[:archived].present?

      if @show_archived
        scope = Llm.with_archived.where.not(archived_at: nil)
      else
        scope = Llm.all
      end
      scope = scope.where(api_provider: @provider) if @provider
      scope = scope.where("model ILIKE ?", "%#{@q}%") if @q
      @llms = scope.order(:api_provider, :model)

      @providers = Llm.with_archived.order(:api_provider).distinct.pluck(:api_provider)
      @supported_apis_map = SupportedApi.all.index_by(&:api_base_uri)
    end

    def update
      if @llm.update(llm_params)
        flash.now[:success] = "LLM updated."
      else
        flash.now[:error] = "Failed to update LLM."
      end
      respond_to do |format|
        format.turbo_stream  # This will display the flash message.
        format.html { redirect_back_or_to(admin_llms_path) }
      end
    end

    def archive
      if @llm.archive
        flash[:success] = "LLM archived."
      else
        flash[:error] = @llm.errors.full_messages.to_sentence
      end
      redirect_back_or_to(admin_llms_path)
    end

    def unarchive
      @llm.unarchive
      flash[:success] = "LLM unarchived."
      redirect_back_or_to(admin_llms_path)
    end

    private

    def set_llm
      @llm = Llm.with_archived.find(params[:id])
    end

    def llm_params
      params.require(:llm).permit(:supports_audio_input)
    end
  end
end
