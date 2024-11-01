module Student
  class LessonsController < ApplicationController
    before_action :set_lesson, only: [ :show ]

    def show
      @lesson_progress = @lesson.find_or_create_progress(current_user)
      @conversation = @lesson_progress.find_or_create_conversation(current_user)
    end

    private

    def set_lesson
      @lesson = Lesson.find(params[:id])
    end
  end
end
