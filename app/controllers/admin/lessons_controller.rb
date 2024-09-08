module Admin
  class LessonsController < ApplicationController
    before_action :require_admin
    before_action :set_course
    before_action :set_lesson, only: [ :edit, :update, :destroy ]

    def index
      @lessons = @course.lessons
    end

    def new
      @lesson = @course.lessons.build
    end

    def create
      @lesson = @course.lessons.build(lesson_params)

      if @lesson.save
        redirect_to admin_course_lessons_path(@course), notice: "Lesson was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @lesson.update(lesson_params)
        redirect_to admin_course_lessons_path(@course), notice: "Lesson was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @lesson.destroy
      redirect_to admin_course_lessons_path(@course), notice: "Lesson was successfully deleted."
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
