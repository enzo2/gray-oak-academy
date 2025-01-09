class AppletsController < ApplicationController
  before_action :set_applet, only: [ :show, :destroy ]

  def create
    @applet = Applet.new
    @applet.user = current_user
    @applet.update!(applet_params)
    @applet.save!
    flash[:notice] = "Applet saved!"
    respond_to do |format|
      format.turbo_stream
    end
  end

  def index
    @applets = current_user.applets.order(created_at: :desc)
  end

  def show
  end

  def destroy
    @applet.destroy
    flash[:notice] = "Applet deleted!"
    respond_to do |format|
      format.turbo_stream
    end
  end

  private 
  
  def set_applet
    @applet = Applet.find(params[:id])
  end

  def applet_params
    params.expect(applet: [:title, :code])
  end
end
