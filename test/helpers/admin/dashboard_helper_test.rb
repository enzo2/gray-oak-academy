require "test_helper"

module Admin
  class DashboardHelperTest < ActionView::TestCase
    test "dashboard_y_axis_labels uses the true midpoint for a single-count chart" do
      assert_equal(
        { top: "1", middle: "0.5", bottom: "0" },
        dashboard_y_axis_labels(1)
      )
    end

    test "dashboard_y_axis_labels hides redundant upper ticks when there is no activity" do
      assert_equal(
        { top: nil, middle: nil, bottom: "0" },
        dashboard_y_axis_labels(0)
      )
    end
  end
end
