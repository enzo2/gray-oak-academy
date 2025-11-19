class AppletsController < ApplicationController
  before_action :set_applet, only: [ :show, :destroy, :save_as_resource ]

  # POST /applets, via code_executor_controller
  def create
    @applet = Applet.new(user: current_user)
    @applet.assign_attributes(applet_params)

    if @applet.save
      flash.now[:success] = "Applet saved successfully!"
      respond_to do |format|
        format.turbo_stream
      end
    else
      flash.now[:error] = @applet.errors.full_messages.join(", ") || "Failed to save applet."
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_content }
      end
    end
  end

  def index
    @applets = current_user.applets.order(created_at: :desc)
    # If the user is an admin, render with the admin layout.
    if current_user.role_teacher?
      render :index, layout: "admin/base"
    end
    # Student dashboard doesn't use the index template.
  end

  # No individual page for applets; this returns JSON for copying to clipboard
  def show
     render json: { code: @applet.code }
  end

  def destroy
    @applet.destroy
    flash.now[:success] = "Applet deleted!"
    respond_to do |format|
      format.turbo_stream
    end
  end

  def save_as_resource
    resource = Resource.new(
      category: "Applet",
      teacher: current_user
    )
    resource.applet = @applet
    if resource.save
      flash[:success] = "Applet saved as resource!"
      redirect_to admin_resources_path
    else
      flash[:error] = resource.errors.full_messages.join(", ")
      redirect_to applets_path
    end
  end

  private

  def set_applet
    @applet = Applet.find(params[:id])
  end

  def applet_params
    params.expect(applet: [ :title, :code ])
  end
end
