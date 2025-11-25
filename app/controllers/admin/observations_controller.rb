module Admin
  class ObservationsController < Admin::BaseController
    def update
      @observation = Observation.find(params[:id])

      # Authorization
      unless @observation.student.teacher == current_user || current_user.role_superuser?
        head :forbidden
        return
      end

      if @observation.update(observation_params)
        if @observation.status_approved?
          @observation.touch(:last_validated_at)
        end

        respond_to do |format|
          format.turbo_stream { render :update }
          format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal) }
        end
      else
        head :unprocessable_content
      end
    end

    private

    def observation_params
      params.require(:observation).permit(:status)
    end
  end
end
