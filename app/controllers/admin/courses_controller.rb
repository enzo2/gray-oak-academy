module Admin
  class CoursesController < ApplicationController
    before_action :require_admin
    before_action :set_course, only: [ :edit, :update, :destroy ]

    def index
      @courses = Course.all
    end

    def new
      @course = Course.new
    end

    def create
      @course = Course.new(course_params)
      @course.teacher = current_user

      if @course.save
        @courses = Course.all
        render turbo_stream:
          turbo_stream.replace("dashboard-content", template: "admin/courses/index", locals: { courses: @courses })
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @course.update(course_params)
        redirect_to admin_courses_path, notice: "Course was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @course.destroy
      redirect_to admin_courses_path, notice: "Course was successfully deleted."
    end

    private

    def set_course
      @course = Course.find(params[:id])
    end

    def course_params
      params.require(:course).permit(:title, :summary, :outline, :grade_level)
    end
  end
end
