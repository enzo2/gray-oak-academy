class EnrollmentsController < ApplicationController
  before_action :set_enrollment, only: [ :show ]
  layout :enrollment_layout

  def show
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  private

  def set_enrollment
    @enrollment = Enrollment.find(params[:id])
  end

  def enrollment_layout
    current_user.role_teacher? ? "admin/base" : "application"
  end
end
