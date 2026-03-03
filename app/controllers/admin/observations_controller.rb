module Admin
  class ObservationsController < Admin::BaseController
    before_action :set_observation, only: [ :show, :edit, :update, :revalidate, :destroy ]
    before_action :authorize_observation_access!, only: [ :show, :edit, :update, :revalidate, :destroy ]
    before_action :set_stream_context, only: [ :show, :edit, :update, :revalidate, :destroy ]

    include ActionView::RecordIdentifier

    def show; end

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

      return unless authorize_student_access!(@student)

      if @observation.save
        if request.format.turbo_stream?
          @observation_sort = Observation.normalize_management_sort(params[:observation_sort])
          @observation_sort_options = Observation.management_sort_options
          @observation_timeline = Observation.for_management_timeline(
            student: @student,
            sort: @observation_sort,
            as_of: Time.current
          )
        end

        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to admin_student_path(@student, active_tab: :journal_timeline) }
        end
      else
        head :unprocessable_content
      end
    end

    def edit; end

    def update
      @observation.assign_attributes(observation_params)

      if @observation.status_changed? && @observation.status_approved?
        @observation.last_validated_at = Time.current
      end

      if @observation.save
        respond_to do |format|
          format.turbo_stream { render :update }
          format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal_timeline) }
        end
      else
        head :unprocessable_content
      end
    end

    def destroy
      @observation.destroy
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal_timeline) }
      end
    end

    def revalidate
      unless @observation.status_approved?
        respond_to do |format|
          format.turbo_stream { head :unprocessable_content }
          format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal_timeline), alert: "Only approved observations can be re-validated." }
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
          format.html { redirect_to admin_student_path(@observation.student, active_tab: :journal_timeline), notice: "Observation re-validated." }
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

    def set_stream_context
      @frame_id_prefix = sanitized_dom_prefix(params[:frame_id_prefix])
      @entry_dom_id_prefix = sanitized_dom_prefix(params[:entry_dom_id_prefix])
    end

    def authorize_observation_access!
      authorize_student_access!(@observation.student)
    end

    def authorize_student_access!(student)
      return true if student.teacher == current_user || current_user.role_superuser?

      head :forbidden
      false
    end

    def sanitized_dom_prefix(value)
      prefix = value.to_s.strip
      return nil if prefix.blank?
      return prefix if prefix.match?(/\A[a-zA-Z0-9_-]+\z/)

      nil
    end
  end
end
