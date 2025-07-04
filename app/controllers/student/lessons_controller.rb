module Student
  class LessonsController < ApplicationController
    before_action :set_lesson, only: [ :show ]
    before_action :require_llm_configured, only: [ :show ]

    def show
      # Initiate a lesson_progress and associated conversation if this is the first time the user is accessing the lesson
      @lesson_progress = @lesson.find_or_create_progress(current_user)
      @conversation = @lesson_progress.find_or_create_conversation(current_user)
    end

    private

    def set_lesson
      @lesson = Lesson.find(params[:id])
    end
  end
end
