require "test_helper"

class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  test "redirects unauthenticated users to login" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "redirects students to student root with alert" do
    student = users(:student)
    sign_in student
    get admin_root_path
    assert_redirected_to student_root_path
    assert_equal "You must be an admin to access this page.", flash[:alert]
  end

  test "allows admins to access admin pages" do
    admin = users(:admin)
    sign_in admin
    get admin_root_path
    assert_response :success
  end

  test "allows superusers to access admin pages" do
    # Create a superuser or modify an existing one (since there is no superuser fixture by default usually, unless I missed it)
    # Checking fixtures... users.yml usually has admin.
    # I'll promote an admin to superuser for this test or check if there is a superuser role.
    superuser = users(:admin)
    superuser.update_column(:role, "superuser")

    sign_in superuser
    get admin_root_path
    assert_response :success
  end
end
