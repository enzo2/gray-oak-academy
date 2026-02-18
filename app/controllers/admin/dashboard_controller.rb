module Admin
  class DashboardController < Admin::BaseController
    before_action :check_llm_configured

    def dashboard
      @dashboard = Admin::TeacherDashboardDataService.call(teacher: current_user)
    end
  end
end
