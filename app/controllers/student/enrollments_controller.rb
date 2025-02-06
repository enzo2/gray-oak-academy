module Student
  class EnrollmentsController < ApplicationController
    before_action :set_enrollment, only: [ :show ]

    def show
    end

    private

    def set_enrollment
      @enrollment = Enrollment.find(params[:id])
    end
  end
end
