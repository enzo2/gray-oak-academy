class Admin::ResourcesController < AdminController
  before_action :set_resource, only: [ :show, :edit, :update, :destroy, :delete_file ]
  before_action :set_lesson_plan, only: [ :create ]

  def index
    @resources = Resource.all
  end

  def show
  end

  def new
    @resource = Resource.new
  end

  def create
    @resource = Resource.new(resource_params)
    if @resource.save
      if @lesson_plan
        @lesson_plan.resources << @resource
        respond_to do |format|
          format.turbo_stream
          # format.html { redirect_to admin_resources_path }
        end
      else
        redirect_to admin_resources_path, notice: "Resource was successfully created."
      end
    else
      respond_to do |format|
        # format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @resource.update(resource_params)
      redirect_to admin_resources_path, notice: "Resource was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @resource.destroy
    redirect_to admin_resources_path, notice: "Resource was successfully destroyed."
  end

  def delete_file
    @resource.file.purge
    redirect_to admin_resource_path(@resource), notice: "File was successfully deleted."
  end

  private

  def set_resource
    @resource = Resource.find(params[:id])
  end

  def set_lesson_plan
    @lesson_plan = LessonPlan.find(params[:lesson_plan_id]) if params[:lesson_plan_id]
  end

  def resource_params
    params.require(:resource).permit(:category, :description, :uri, :file)
  end
end
