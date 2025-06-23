module Admin
  class LessonsController < Admin::BaseController
    before_action :set_course
    before_action :set_lesson, only: [ :show, :edit, :update, :destroy, :move_higher, :move_lower ]

    def index
      @lessons = @course.lessons
    end

    def show
    end

    def new
      @lesson = @course.lessons.build
    end

    def create
      @lesson = @course.lessons.build(lesson_params)

      if @lesson.save
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
      if @lesson.update(lesson_params)
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
      @lesson.destroy
      redirect_to admin_course_lessons_path(@course), status: :see_other
    end

    def generate_lessons
      GenerateCourseLessonsJob.perform_later(@course, current_user)
      head :accepted  # No view needed. The Job will broadcast when done.
    end

    def move_higher
      @lesson.move_higher
      respond_to do |format|
        format.turbo_stream
      end
    end

    def move_lower
      @lesson.move_lower
      respond_to do |format|
        format.turbo_stream
      end
    end

    def printable
      render layout: false
    end

    private

    def set_course
      @course = Course.find(params[:course_id])
    end

    def set_lesson
      @lesson = @course.lessons.find(params[:id])
    end

    def lesson_params
      params.require(:lesson).permit(:title, :goals, :approx_duration_min)
    end
  end
end
