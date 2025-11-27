module Admin
  class ObservationsController < Admin::BaseController
    before_action :set_observation, only: [ :show, :edit, :update, :destroy ]

    include ActionView::RecordIdentifier

    def show
      # Authorization
      unless @observation.student.teacher == current_user || current_user.role_superuser?
        head :forbidden
      end
    end

    def create
      @student = User.find(params[:observation][:student_id])

      # Authorization
      unless @student.teacher == current_user || current_user.role_superuser?
        head :forbidden
        return
      end

      @observation = Observation.new(observation_params)
      @observation.student = @student
      @observation.author = current_user
      @observation.status = :approved # Teacher-created observations are auto-approved
      @observation.last_validated_at = Time.current

      if @observation.save
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to admin_student_path(@student, active_tab: :journal) }
        end
      else
        head :unprocessable_content
      end
    end

    def edit
      # Authorization
      unless @observation.student.teacher == current_user || current_user.role_superuser?
        head :forbidden
        nil
      end
    end

    def update
      # Authorization
      unless @observation.student.teacher == current_user || current_user.role_superuser?
        head :forbidden
        return
      end

      @observation.assign_attributes(observation_params)

      if @observation.status_changed? && @observation.status_approved?
        @observation.last_validated_at = Time.current
      end

      if @observation.save
        respond_to do |format|
          format.turbo_stream { render :update }
          format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal) }
        end
      else
        head :unprocessable_content
      end
    end

    def destroy
      # Authorization
      unless @observation.student.teacher == current_user || current_user.role_superuser?
        head :forbidden
        return
      end

      @observation.destroy
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove("#{dom_id(@observation)}_card_container") }
        format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal) }
      end
    end

    private

    def set_observation
      @observation = Observation.find(params[:id])
    end

    def observation_params
      params.require(:observation).permit(:status, :content)
    end
  end
end
