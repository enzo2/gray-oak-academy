require "application_system_test_case"

class AdminStudentsTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @student = users(:student)
  end

  test "admin can view students index" do
    sign_in @admin
    visit admin_students_path
    assert_text "Manage Students"
    assert_text @student.name
  end

  test "admin can adopt and unadopt a student" do
    sign_in @admin
    visit admin_students_path
    assert_text @student.name
    # Click the adopt icon button for the student (disambiguate by matching the correct tree item and student name)
    student_tree_items = all("sl-tree-item").select do |item|
      item.has_selector?("span", text: @student.name)
    end
    # Find the adopt button within the correct tree item by looking for the span with the student name and then the button in the same div
    adopt_button = student_tree_items.first.find(:xpath, ".//div[span[text()='#{@student.name}']]/a/sl-icon-button[@label='Adopt']", visible: true)
    adopt_button.click
    assert_text "Student adopted successfully."
    # After adoption, go to the settings tab and click the unadopt button
    visit admin_student_path(@student)
    find('sl-tab[panel="settings"]').click
    # Accept the confirmation dialog for unadopting
    page.accept_confirm do
      click_button "Un-adopt student"
    end
    assert_text "Student unadopted successfully."
  end
end
