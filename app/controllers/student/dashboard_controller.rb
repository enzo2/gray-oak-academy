module Student
  class DashboardController < ApplicationController
    before_action :check_llm_configured

    def dashboard
      @enrollments = current_user.enrollments.includes(:course)
      @applets = current_user.applets

      # Perform verification that the course reports were generated, in case the job failed originally
      @enrollments.each do |enrollment|
        enrollment.course_report_check if enrollment.completed?
      end
    end

    def journal
      page = params[:page].present? ? params[:page].to_i : 1
      per_page = 25
      @timeline_items = JournalService.get_timeline(current_user, teacher_mode: false, page: page, per_page: per_page)

      respond_to do |format|
        format.turbo_stream do
          streams = []
          streams << turbo_stream.append("journal_entries", partial: "shared/journal_entry", collection: @timeline_items, as: :item, locals: { teacher_mode: false })

          if @timeline_items.size < per_page
            streams << turbo_stream.update("journal_pagination", partial: "shared/journal_end")
          end

          render turbo_stream: streams
        end
      end
    end
  end
end
