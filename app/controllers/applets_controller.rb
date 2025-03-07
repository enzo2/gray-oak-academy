class AppletsController < ApplicationController
  before_action :set_applet, only: [ :show, :destroy ]

  # Request is made from the Stimulus controller.
  # It would be simpler to use a form submission so we can respond with a turbo_stream template & flash message.
  def create
    @applet = Applet.new(user: current_user)
    @applet.update!(applet_params)
    @applet.save!
    render json: { id: @applet.id }
  end

  def index
    @applets = current_user.applets.order(created_at: :desc)
  end

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

  private

  def set_applet
    @applet = Applet.find(params[:id])
  end

  def applet_params
    params.expect(applet: [ :title, :code ])
  end
end
