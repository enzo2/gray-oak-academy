module Admin
  class ResourcesController < Admin::BaseController
    before_action :set_resource, only: [ :show, :edit, :update, :destroy, :delete_file, :approve ]

    def index
      # Only show the current teacher's resources
      @resources = Resource.where(teacher: current_user)
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
      redirect_back fallback_location: admin_resources_path, notice: "Resource approved."
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
