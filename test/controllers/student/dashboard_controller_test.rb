require "test_helper"

module Student
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "dashboard defaults to courses active tab" do
      sign_in users(:student)

      get student_root_path

      assert_response :success
      assert_match 'data-controller="tabs"', response.body
      assert_match 'data-tabs-active-tab-value="courses"', response.body
    end

    test "dashboard accepts allowed active tab param" do
      sign_in users(:student)

      get student_root_path(active_tab: :past_courses)

      assert_response :success
      assert_match 'data-tabs-active-tab-value="past_courses"', response.body
    end

    test "dashboard falls back to courses for unknown active tab" do
      sign_in users(:student)

      get student_root_path(active_tab: :unknown_tab)

      assert_response :success
      assert_match 'data-tabs-active-tab-value="courses"', response.body
    end
  end
end
