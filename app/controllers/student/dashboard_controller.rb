module Student
  class DashboardController < ApplicationController
    def dashboard
      @enrollments = current_user.enrollments.includes(:course)
      @applets = current_user.applets
    end
  end
end
