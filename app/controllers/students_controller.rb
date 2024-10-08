class StudentsController < ApplicationController
  def dashboard
    @enrollments = current_user.enrollments.includes(:course)
  end
end
