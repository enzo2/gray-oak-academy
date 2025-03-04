module Admin
  class CompletionsController < ApplicationController
    before_action :require_admin

    def index
      @usage_data = if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        Completion.date_ranged_usage_data(start_date, end_date)
      else
        Completion.all_time_usage_data
      end
    end
  end
end
