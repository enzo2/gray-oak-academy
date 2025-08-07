module Admin
  class CompletionsController < Admin::BaseController
    def index
      @users = User.all.order(:email)
      @teachers = User.all.select(&:role_teacher?).sort_by(&:email)

      base_completions = determine_base_completions

      if params[:start_date].present? && params[:end_date].present?
        @start_date = Date.parse(params[:start_date])
        @end_date = Date.parse(params[:end_date])
        @usage_data = base_completions.in_date_range(@start_date, @end_date).usage_data_query
      else
        @usage_data = base_completions.all_time_usage_data
      end
    end

    private

    def determine_base_completions
      if current_user.role_superuser?
        if params[:filter_by_user_id].present?
          Completion.for_user_ids(params[:filter_by_user_id])
        elsif params[:filter_by_teacher_id].present?
          teacher = User.find(params[:filter_by_teacher_id])
          user_ids = [ teacher.id ] + teacher.students.pluck(:id)
          Completion.for_user_ids(user_ids)
        else
          # Superusers see the entire database's usage data
          Completion.all
        end
      elsif current_user.role_admin?
        case params[:filter_by_scope]
        when "user"
          Completion.for_user_ids(current_user.id)
        when "students"
          Completion.for_user_ids(current_user.students.pluck(:id))
        else
          # Teachers are restricted to seeing usage data for themselves and their students
          user_ids = [ current_user.id ] + current_user.students.pluck(:id)
          Completion.for_user_ids(user_ids)
        end
      end
    end
  end
end
