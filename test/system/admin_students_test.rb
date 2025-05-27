require "application_system_test_case"

class AdminStudentsTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @student = users(:student2)
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
    # Find the sl-tree-item containing the student's name
    student_tree_item = all("sl-tree-item").find do |item|
      item.has_text?(@student.name)
    end
    # Within that tree item, find the adopt button by label
    adopt_button = student_tree_item.find('[label="Adopt"]', visible: true)
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
