module Admin
  class CoursesController < Admin::BaseController
    before_action :set_course, only: [ :edit, :update, :destroy, :generate_outline, :archive, :unarchive ]

    def index
      @active_courses =   Course.status_active.where(teacher: current_user).order(created_at: :desc)
      @archived_courses = Course.status_archived.where(teacher: current_user).order(created_at: :desc)
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
      redirect_to admin_courses_path, status: :see_other
    end

    # POST /admin/courses/:id/archive
    def archive
      @course.update!(status: :archived)
      redirect_to admin_courses_path, status: :see_other
    end

    # POST /admin/courses/:id/unarchive
    def unarchive
      @course.update!(status: :active)
      redirect_to admin_courses_path, status: :see_other
    end

    # POST /admin/courses/:id/generate_outline
    def generate_outline
      # Enqueue the background job
      GenerateCourseOutlineJob.perform_later(@course, current_user)
      head :accepted # No view needed. The Job will broadcast when done.
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
