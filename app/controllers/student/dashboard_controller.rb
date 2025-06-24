module Student
  class DashboardController < ApplicationController
    def dashboard
      @enrollments = current_user.enrollments.includes(:course)
      @applets = current_user.applets

      # Perform verification that the course reports were generated, in case the job failed originally
      @enrollments.each do |enrollment|
        enrollment.course_report_check if enrollment.completed?
      end
    end
  end
end
