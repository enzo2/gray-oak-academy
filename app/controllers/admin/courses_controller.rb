module Admin
  class CoursesController < ApplicationController
    before_action :require_admin
    before_action :set_course, only: [ :edit, :update, :destroy, :generate_outline ]

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

    # POST /admin/courses/:id/generate_outline
    def generate_outline
      # Enqueue the background job
      GenerateCourseOutlineJob.perform_later(@course)

      respond_to do |format|
        format.turbo_stream # renders a spinner
      end
    end

    private

    def set_course
      @course = Course.find(params[:id])
    end

    def course_params
      # Extract the keys and values for outline
      outline_topics = params[:course].delete(:outline_topics) || []
      outline_details = params[:course].delete(:outline_details) || []

      # Zip the topics and details into an array of arrays [ [topic1, details1], [topic2, details2], ...
      # And then map it to an array of hashes [ { topic1 => details1 }, { topic2 => details2 }, ... ]
      outline = outline_topics.zip(outline_details).map { |topic, details| { topic => details } }

      params.require(:course).permit(:title, :summary, :grade_level).tap do |whitelisted|
        whitelisted[:outline] = outline
      end
    end
  end
end
