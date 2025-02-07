module Student
  class EnrollmentsController < ApplicationController
    before_action :set_enrollment, only: [ :show ]

    def show
      respond_to do |format|
        format.turbo_stream
        # format.html
      end
    end

    private

    def set_enrollment
      @enrollment = Enrollment.find(params[:id])
    end
  end
end
