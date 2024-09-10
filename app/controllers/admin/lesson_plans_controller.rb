module Admin
  class LessonPlansController < ApplicationController
    before_action :require_admin
    before_action :set_lesson

    def edit
      @lesson_plan = @lesson.lesson_plan || @lesson.build_lesson_plan(teacher: current_user)
    end

    def update
      @lesson_plan = @lesson.lesson_plan || @lesson.build_lesson_plan(teacher: current_user)

      if @lesson_plan.update(lesson_plan_params)
        # redirect_to admin_course_lessons_path(@lesson.course), notice: "Lesson plan was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_lesson
      @lesson = Lesson.find(params[:lesson_id])
    end

    def lesson_plan_params
      params.require(:lesson_plan).permit(:content, :status)
    end
  end
end
