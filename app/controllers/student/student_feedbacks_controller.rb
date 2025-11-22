module Student
  class StudentFeedbacksController < ApplicationController
    def create
      @feedback = current_user.student_feedbacks.new(feedback_params)
      # Try to link to current lesson progress if available via session or param, but param is safer
      # params[:student_feedback][:lesson_progress_id]

      if @feedback.save
        flash.now[:success] = "Thank you for your feedback!"
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("flash_bar", partial: "shared/flash")
            ]
          end
        end
      else
        head :unprocessable_content
      end
    end

    private

    def feedback_params
      params.require(:student_feedback).permit(:content, :lesson_progress_id)
    end
  end
end
