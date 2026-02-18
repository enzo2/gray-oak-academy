require "application_system_test_case"

class AdminStudentsTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @my_student = users(:student)
    @other_student = users(:student2)
  end

  test "admin can view students index" do
    sign_in @admin
    visit admin_students_path
    assert_text "Manage Students"
    assert_text @my_student.name
    other_students_expand_tree_button = find("button", text: "Other Students")
    other_students_expand_tree_button.click
    assert_text @other_student.name
  end

  test "admin can adopt and unadopt a student" do
    sign_in @admin
    visit admin_students_path
    other_students_expand_tree_button = find("button", text: "Other Students")
    other_students_expand_tree_button.click
    # Find the other student's name
    student_tree_item = all("div#other-students-content div").find do |item|
      item.has_text?(@other_student.name)
    end
    # Within that tree item, find the adopt button
    adopt_button = student_tree_item.find("svg", visible: true)
    adopt_button.click
    assert_text "Student adopted successfully."
    # After adoption, go to the settings tab and click the unadopt button
    visit admin_student_path(@other_student)
    find('#student-dashboard-tabs [role="tab"][data-tabs-panel="settings"]').click
    # Accept the confirmation dialog for unadopting
    page.accept_confirm do
      click_button "Release student"
    end
    assert_text "Student unadopted successfully."
  end

  test "mobile student list opens and closes with a single nav instance" do
    sign_in @admin
    begin
      page.current_window.resize_to(375, 812)
      visit admin_students_path

      assert_selector "sl-icon-button[label='Open student list']"
      assert_selector "#new-student-modal", count: 1, visible: :all

      find("sl-icon-button[label='Open student list']").click
      assert_selector "#students-mobile-sidebar:not(.hidden)", wait: 5

      execute_script("document.querySelector('#students-mobile-backdrop').click()")
      assert_no_selector "#students-mobile-sidebar:not(.hidden)", wait: 5
      assert_selector "#new-student-modal", count: 1, visible: :all
    ensure
      page.current_window.resize_to(1400, 1400)
    end
  end

  test "courses tab remains selected after choosing a courses submenu item" do
    sign_in @admin
    visit admin_student_path(@my_student)

    find('#student-dashboard-tabs [role="tab"][data-tabs-group="active_courses past_courses enroll"]').click
    click_button "Past Courses"

    assert_selector '#student-dashboard-tabs [role="tab"][data-tabs-group="active_courses past_courses enroll"][data-state="open"]'
    assert_selector "#past_courses:not(.hidden)"
  end

  test "invalid active tab param falls back to journal panel" do
    sign_in @admin
    visit admin_student_path(@my_student, active_tab: :unknown_tab)

    assert_selector '#student-dashboard-tabs [role="tab"][data-tabs-panel="journal"][data-state="open"]'
    assert_selector "#journal:not(.hidden)"
  end
end
