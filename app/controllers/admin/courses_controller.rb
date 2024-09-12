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
        respond_to do |format|
          format.turbo_stream
        end
      else
        respond_to do |format|
          format.turbo_stream { render :create, status: :unprocessable_entity }
        end
      end
    end

    def edit
      respond_to do |format|
        format.turbo_stream
      end
    end

    def update
      if @course.update(course_params)
        respond_to do |format|
          format.turbo_stream
        end
      else
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @course.destroy
      respond_to do |format|
        format.turbo_stream
      end
    end

    private

    def set_course
      @course = Course.find(params[:id])
    end

    def course_params
      # Extract `outline_keys` and `outline_values` from params, default empty arrays if not present
      outline_keys = params[:course].delete(:outline_keys) || []
      outline_values = params[:course].delete(:outline_values) || []

      # Zip the keys and values into a hash and store it as `outline`
      outline = outline_keys.zip(outline_values).to_h

      # Permit other course attributes and include the manifest `outline` hash
      params.require(:course).permit(:title, :summary, :grade_level).tap do |whitelisted|
        whitelisted[:outline] = outline
      end
    end
  end
end
