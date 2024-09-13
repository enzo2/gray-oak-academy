module Admin
  class LessonPlansController < ApplicationController
    before_action :require_admin
    before_action :set_lesson

    def generate
      # Auto-generate lesson plan content using LLM
    end

    def edit
      @lesson_plan = @lesson.lesson_plan || @lesson.build_lesson_plan(teacher: current_user)
      # Render the edit form for the lesson plan
      respond_to do |format|
        format.turbo_stream
      end
    end

    def update
      @lesson_plan = @lesson.lesson_plan || @lesson.build_lesson_plan(teacher: current_user)

      if @lesson_plan.update(lesson_plan_params)
        respond_to do |format|
          format.turbo_stream
        end
      else
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_entity }
        end
      end
    end

    private

    def set_lesson
      @lesson = Lesson.find(params[:lesson_id])
    end

    def lesson_plan_params
      # Extract `content_keys` and `content_values` from params, default empty arrays if not present
      content_keys = params[:lesson_plan].delete(:content_keys) || []
      content_values = params[:lesson_plan].delete(:content_values) || []

      # Zip the keys and values into a hash and store it as `content`
      content = content_keys.zip(content_values).to_h

      # Permit lesson_plan attributes and include the content hash
      params.require(:lesson_plan).permit(:status).merge(content: content)
    end
  end
end
