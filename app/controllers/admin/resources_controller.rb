module Admin
  class ResourcesController < Admin::BaseController
    before_action :set_resource, only: [ :show, :edit, :update, :destroy, :delete_file, :approve, :check_uri ]

    def index
      # Only show the current teacher's resources
      @resources = Resource.where(teacher: current_user)
                           .includes(:applet)
                           .order(Arel.sql("CASE WHEN approved = FALSE THEN 0 ELSE 1 END ASC"))
                           .order(created_at: :desc)
    end

    def tag_chips
      @tag_values = Resource.normalize_tags(params[:combobox_values])
      respond_to do |format|
        format.turbo_stream
      end
    end

    def show
    end

    def new
      @resource = Resource.new
    end

    def create
      # May submit the form from Resources dashboard (new available resource), or Lesson Plan dashboard (link to the plan upon creation)
      # Remove the lesson_plan_id since it's not part of resource_params (there's a join table for HABTM relationship)
      @lesson_plan = LessonPlan.find(params[:resource].delete(:lesson_plan_id)) if params[:resource][:lesson_plan_id].present?
      @resource = Resource.new(resource_params)
      @resource.teacher = current_user
      @resource.category = "Applet" if @resource.applet

      if @resource.save
        if @lesson_plan
          @lesson_plan.resources << @resource # Add resource to lesson plan
          respond_to do |format|
            format.turbo_stream
          end
        else
          redirect_to admin_resources_path
        end
      else
        respond_to do |format|
          format.turbo_stream { render :create, status: :unprocessable_content }
        end
      end
    end

    def edit
    end

    def update
      if @resource.update(resource_params)
        redirect_to admin_resources_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @resource.destroy
      redirect_to admin_resources_path
    end

    def delete_file
      @resource.file.purge
      redirect_to admin_resource_path(@resource)
    end

    def approve
      @resource.update!(approved: true)
      @lesson_plan = LessonPlan.find(params[:lesson_plan_id]) if params[:lesson_plan_id].present?
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: admin_resources_path, notice: "Resource approved." }
      end
    end

    def check_uri
      if @resource.uri.blank?
        flash.now[:alert] = "No URI to check."
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.update("flash_bar", partial: "shared/flash") }
          format.html { redirect_to admin_resource_path(@resource), alert: "No URI to check." }
        end
        return
      end

      @uri_check_result = UrlEmbeddabilityService.check(url: @resource.uri)
      status = @uri_check_result[:status].to_s
      final_url = @uri_check_result[:final_url].to_s
      reason = @uri_check_result[:reason].to_s

      message = "URI check: #{status}. #{reason}"
      message += " Final URL: #{final_url}" if final_url.present? && final_url != @resource.uri

      flash_type = %w[blocked_xfo blocked_csp unknown].include?(status) ? :alert : :notice
      flash.now[flash_type] = message

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_resource_path(@resource), flash_type => message }
      end
    rescue UrlEmbeddabilityService::ValidationError => e
      flash.now[:alert] = "URI check failed: #{e.message}"
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.update("flash_bar", partial: "shared/flash") }
        format.html { redirect_to admin_resource_path(@resource), alert: "URI check failed: #{e.message}" }
      end
    end

    private

    def set_resource
      if current_user.role_superuser?
        @resource = Resource.find(params[:id])
      else
        @resource = Resource.where(teacher: current_user).find(params[:id])
      end
    end

    def resource_params
      params.expect(resource: [ :category, :description, :uri, :content, :file, :include_by_default, :tags, applet_attributes: [ :id, :title, :code ] ])
      # Could add _destroy for applet_attributes if want to allow deleting applets, but makes sense to delete the whole resource
    end
  end
end
