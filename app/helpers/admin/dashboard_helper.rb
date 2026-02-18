module Admin
  module DashboardHelper
    def dashboard_bar_height(count, max_count)
      return "0%" if count.to_i <= 0 || max_count.to_i <= 0

      height = ((count.to_f / max_count) * 100).round
      "#{[height, 6].max}%"
    end
  end
end
