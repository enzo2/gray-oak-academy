class Admin::ResourcesController < AdminController
  before_action :set_resource, only: [ :show, :edit, :update, :destroy, :delete_file ]

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
      redirect_to admin_resources_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @resource.update(resource_params)
      redirect_to admin_resources_path
    else
      render :edit, status: :unprocessable_entity
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

  private

  def set_resource
    @resource = Resource.find(params[:id])
  end

  def resource_params
    params.require(:resource).permit(:category, :description, :uri, :file)
  end
end
