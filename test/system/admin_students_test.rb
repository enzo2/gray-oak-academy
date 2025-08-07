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
    find('sl-tab[panel="settings"]').click
    # Accept the confirmation dialog for unadopting
    page.accept_confirm do
      click_button "Release student"
    end
    assert_text "Student unadopted successfully."
  end
end
