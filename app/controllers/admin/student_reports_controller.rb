module Admin
  class StudentReportsController < Admin::BaseController
    before_action :set_student_report
    before_action :set_context

    def show; end

    def edit; end

    def update
      fields = student_report_params.fetch(:report_fields, {})

      if @student_report.apply_teacher_edits(fields, editor: current_user)
        respond_to do |format|
          format.turbo_stream do
            flash.now[:notice] = "Report updated. Future tutoring will use the correction."
          end
          format.html do
            redirect_to admin_student_report_path(@student_report, context: @context),
                        notice: "Report updated. Future tutoring will use the correction."
          end
        end
      else
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_content }
          format.html { render :edit, status: :unprocessable_content }
        end
      end
    end

    private

    def set_student_report
      @student_report = StudentReport
        .where(student: authorized_student_scope(include_self: true))
        .find(params[:id])

      raise ActiveRecord::RecordNotFound unless @student_report.teacher_editable?
    end

    def set_context
      @context = params[:context].to_s.presence_in(%w[journal enrollment]) || "journal"
    end

    def student_report_params
      params.require(:student_report).permit(report_fields: {})
    end
  end
end
