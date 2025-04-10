module Student
  class StudentsController < ApplicationController
    def dashboard
      @enrollments = current_user.enrollments.includes(:course)
      @applets = current_user.applets
    end
  end
end
