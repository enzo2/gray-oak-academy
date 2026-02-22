module Admin
  class ObservationsController < Admin::BaseController
    before_action :set_observation, only: [ :show, :edit, :update, :revalidate, :destroy ]

    include ActionView::RecordIdentifier

    def show
      # Authorization
      unless @observation.student.teacher == current_user || current_user.role_superuser?
        head :forbidden
      end
    end

    def create
      @observation = Observation.new(observation_params)
      @observation.author = current_user
      @observation.status = :approved # Teacher-created observations are auto-approved
      @observation.last_validated_at = Time.current
      @student = @observation.student

      if @student.nil?
        head :not_found
        return
      end

      # Authorization
      unless @student.teacher == current_user || current_user.role_superuser?
        head :forbidden
        return
      end

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
        format.turbo_stream
        format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal) }
      end
    end

    def revalidate
      # Authorization
      unless @observation.student.teacher == current_user || current_user.role_superuser?
        head :forbidden
        return
      end

      unless @observation.status_approved?
        respond_to do |format|
          format.turbo_stream { head :unprocessable_content }
          format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal), alert: "Only approved observations can be re-validated." }
        end
        return
      end

      @observation.last_validated_at = Time.current

      if @observation.save
        respond_to do |format|
          format.turbo_stream do
            flash.now[:notice] = "Observation re-validated."
            render :update
          end
          format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal), notice: "Observation re-validated." }
        end
      else
        head :unprocessable_content
      end
    end

    private

    def set_observation
      @observation = Observation.find(params[:id])
    end

    def observation_params
      params.require(:observation).permit(:status, :content, :student_id)
    end
  end
end
