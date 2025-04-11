module Admin
  class LessonPlansController < Admin::BaseController
    before_action :set_lesson
    before_action :set_lesson_plan, only: [ :edit, :update, :destroy, :link_resource, :unlink_resource, :new_resource, :generate_content ]

    def edit
      # Render the edit form for the lesson plan
    end

    def update
      if @lesson_plan.update(lesson_plan_params)
        flash.now[:success] = "Updated succcessfully."
        respond_to do |format|
          format.turbo_stream
        end
      else
        flash.now[:error] = "Failed to update lesson plan. #{@lesson_plan.errors.full_messages.join(', ')}"
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      @lesson_plan.destroy
      redirect_to admin_course_lessons_path(@lesson.course), status: :see_other
    end

    def link_resource
      @resource = Resource.find(params[:resource_id])
      @lesson_plan.resources << @resource unless @lesson_plan.resources.include?(@resource)
      @lesson_plan.save!

      respond_to do |format|
        format.turbo_stream
      end
    end

    def unlink_resource
      @resource = Resource.find(params[:resource_id])
      @lesson_plan.resources.delete(@resource)

      respond_to do |format|
        format.turbo_stream
      end
    end

    def new_resource
      # Renders the form to create a new resource for the lesson plan
      # Persist the lesson plan so the form has an id to attach the resource
      @lesson_plan.save! if @lesson_plan.new_record?
      respond_to do |format|
        format.turbo_stream
      end
    end

    def generate_content
      # Persist the lesson plan before generating content
      @lesson_plan.save!
      GenerateLessonPlanContentJob.perform_later(@lesson_plan, current_user)
      respond_to do |format|
        format.turbo_stream
      end
    end

    private

    def set_lesson
      @lesson = Lesson.find(params[:lesson_id])
    end

    def set_lesson_plan
      @lesson_plan = @lesson.lesson_plan || @lesson.build_lesson_plan(teacher: current_user)
    end

    def lesson_plan_params
      # Extract `content_keys` and `content_values` from params, default to empty arrays if not present
      content_keys = params[:lesson_plan].delete(:content_keys) || []
      content_values = params[:lesson_plan].delete(:content_values) || []

      # Zip the keys and values into an array of hashes
      # The order is preserved as it comes from the form
      content = content_keys.zip(content_values).map { |type, details| { type => details } }

      # Permit lesson_plan attributes, include the content and chalkboard_enabled
      params.require(:lesson_plan).permit(:status, :chalkboard_enabled).tap do |whitelisted|
        whitelisted[:content] = content
      end
    end
  end
end
