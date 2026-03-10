module Admin
  module DashboardHelper
    def dashboard_bar_height(count, max_count)
      return "0%" if count.to_i <= 0 || max_count.to_i <= 0

      height = ((count.to_f / max_count) * 100).round
      "#{[ height, 6 ].max}%"
    end

    def dashboard_y_axis_labels(max_count)
      max_count = max_count.to_i
      return { top: nil, middle: nil, bottom: "0" } if max_count <= 0

      {
        top: max_count.to_s,
        middle: dashboard_tick_label(max_count / 2.0),
        bottom: "0"
      }
    end

    private

    def dashboard_tick_label(value)
      return value.to_i.to_s if value == value.to_i

      format("%.1f", value).sub(/\.0\z/, "")
    end
  end
end
