require "application_system_test_case"

class StudentDashboardTest < ApplicationSystemTestCase
  setup do
    @student = users(:student2)
  end

  test "student can view dashboard" do
    sign_in @student
    assert_text "Dashboard"
    assert_text "My Courses"
  end
end
