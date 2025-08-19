module Admin
  class SupportedApisController < Admin::BaseController
    before_action :set_supported_api, only: [ :edit, :update, :destroy, :verify_models ]
    before_action :require_superuser, except: [ :index ]

    def index
      @supported_apis = if current_user.role_superuser?
        SupportedApi.order(:api_base_uri)
      else
        # Non-superuser admins: read-only, enabled only
        SupportedApi.enabled.order(:api_base_uri)
      end
    end

    def new
      @supported_api = SupportedApi.new
    end

    def create
      @supported_api = SupportedApi.new(supported_api_params)

      if @supported_api.save
        enqueue_verifications_if_any(@supported_api, params[:models_to_verify])
        redirect_to admin_supported_apis_path, notice: "Supported API created."
      else
        flash.now[:error] = "Failed to create Supported API."
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @verified_models = Llm.where(api_provider: @supported_api.api_base_uri).order(:model)
    end

    def update
      attrs = supported_api_params.dup
      # Do not clear the token if user left it blank on edit
      attrs.delete(:api_access_token) if attrs[:api_access_token].blank?

      if @supported_api.update(attrs)
        enqueue_verifications_if_any(@supported_api, params[:models_to_verify])
        redirect_to admin_supported_apis_path, notice: "Supported API updated."
      else
        flash.now[:error] = "Failed to update Supported API."
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @supported_api.destroy!
      redirect_to admin_supported_apis_path, notice: "Supported API deleted."
    end

    # POST /admin/supported_apis/:id/verify_models
    def verify_models
      models = parse_models(params[:models_to_verify])
      if models.any?
        VerifySupportedApiModelsJob.perform_later(supported_api_id: @supported_api.id, models: models, enqueued_by_user_id: current_user.id)
        redirect_to edit_admin_supported_api_path(@supported_api), notice: "Verification enqueued for #{models.size} model(s)."
      else
        redirect_to edit_admin_supported_api_path(@supported_api), alert: "Please provide at least one model to verify."
      end
    end

    # DEL /admin/supported_apis/:id/models/:model
    def remove_model
      # TODO
    end

    private

    def set_supported_api
      @supported_api = SupportedApi.find(params[:id])
    end

    def supported_api_params
      params.require(:supported_api).permit(
        :api_base_uri,
        :api_access_token,
        :enabled,
        :notes
      )
    end

    def enqueue_verifications_if_any(supported_api, models_param)
      models = parse_models(models_param)
      return if models.empty?
      VerifySupportedApiModelsJob.perform_later(supported_api_id: supported_api.id, models: models, enqueued_by_user_id: current_user.id)
    end

    def parse_models(models_param)
      return [] if models_param.blank?
      models_param
        .to_s
        .split(/[\n,]/)
        .map { |s| s.strip }
        .reject(&:blank?)
        .uniq
    end
  end
end
