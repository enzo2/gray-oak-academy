require "test_helper"

class Admin::StudentsControllerTest < ActionDispatch::IntegrationTest
  test "adopt sets flash error when attempting to adopt self (validate_not_own_teacher)" do
    admin = users(:admin)
    sign_in admin

    # Sanity: admin shouldn't already have a teacher
    assert_nil admin.teacher

    post adopt_admin_student_path(admin.id)

    # Controller redirects with 422 on failure
    assert_response :unprocessable_content
    assert_equal admin_students_url, response.location

    # Flash should surface the model validation message
    assert flash[:error].present?, "Expected flash error to be set"
    assert_match(/cannot be yourself/i, flash[:error])

    # No change persisted
    assert_nil admin.reload.teacher
  end
end
