module Student
  class LessonsController < ApplicationController
    ACCESS_ERROR_MESSAGES = {
      wrong_teacher: "You are not authorized to access this lesson.",
      missing_lesson_plan: "Lesson plan is not available yet.",
      not_enrolled: "You are not enrolled in this course.",
      unpublished_lesson: "This lesson is still in draft and is not available yet.",
      ahead_of_progress: "You can only access your next lesson or earlier lessons."
    }.freeze

    before_action :set_lesson, only: [ :show ]
    before_action :authorize_lesson_access!, only: [ :show ]
    before_action :require_llm_configured, only: [ :show ]

    def show
      # Initiate a lesson_progress and associated conversation if this is the first time the user is accessing the lesson
      @lesson_progress = @lesson.find_or_create_progress(current_user)
      @conversation = @lesson_progress.find_or_create_conversation(current_user)
      @lesson_applet_resources = @lesson_progress.resources.joins(:applet).includes(:applet).order(:id)
    end

    private

    def set_lesson
      @lesson = Lesson.find_by(id: params[:id])
      return if @lesson.present?

      redirect_to student_root_path, alert: "Lesson not found."
    end

    def authorize_lesson_access!
      return if performed?

      status = @lesson.student_access_status_for(current_user)
      return if status == :ok

      redirect_to student_root_path, alert: ACCESS_ERROR_MESSAGES.fetch(status, "You are not authorized to access this lesson.")
    end
  end
end
