module Admin
  class LlmsController < Admin::BaseController
    # before_action :require_superuser   # TODO
    before_action :set_llm

    def update
      if @llm.update(llm_params)
        flash.now[:success] = "LLM updated."
      else
        flash.now[:error] = "Failed to update LLM."
      end
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_user_registration_path(anchor: "llm") }
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
