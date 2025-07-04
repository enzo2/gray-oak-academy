module Admin
  class DashboardController < Admin::BaseController
    before_action :check_llm_configured

    def dashboard
    end
  end
end
