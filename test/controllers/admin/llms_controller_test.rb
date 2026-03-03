require "test_helper"

module Admin
  class LlmsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @superuser = users(:admin)
      @superuser.update_column(:role, "superuser") # Bypass callbacks/validations
      @student = users(:student)

      @llm = Llm.create!(model: "test-llm-controller", api_provider: "https://test.com", context_length: 1000)
    end

    test "should filter archived llms" do
      sign_in @superuser
      archived_llm = Llm.create!(model: "archived-gpt", api_provider: "https://test.com", context_length: 1000, archived_at: Time.current)

      # Default view should NOT show archived
      get admin_llms_url
      assert_response :success
      assert_select "td", text: /archived-gpt/, count: 0

      # Filtered view SHOULD show archived
      get admin_llms_url(archived: "1")
      assert_response :success
      assert_select "td", text: /archived-gpt/
    end

    test "should update llm" do
      sign_in @superuser
      patch admin_llm_url(@llm), params: { llm: { supports_audio_input: true } }
      assert_redirected_to admin_llms_url
      @llm.reload
      assert @llm.supports_audio_input
    end

    test "should archive llm" do
      sign_in @superuser
      patch archive_admin_llm_url(@llm)
      assert_redirected_to admin_llms_url
      @llm.reload
      assert @llm.archived?
    end

    test "should unarchive llm" do
      sign_in @superuser
      @llm.update_column(:archived_at, Time.current)

      patch unarchive_admin_llm_url(@llm)
      assert_redirected_to admin_llms_url
      @llm.reload
      assert_not @llm.archived?
    end

    test "should deny access to regular admin" do
      # Create a regular admin
      regular_admin = User.create!(
        first_name: "Regular",
        last_name: "Admin",
        email: "regular_admin@example.com",
        password: "password",
        role: "admin",
        signup_code: ENV["TEACHER_SIGNUP_CODE"] || "teacher_code"
      )

      sign_in regular_admin

      get admin_llms_url
      # Should be redirected to admin root (dashboard) with alert
      assert_redirected_to admin_root_path
    end

    test "should deny access to student" do
      # Create student manually to ensure password is known
      student = User.create!(
        first_name: "Test",
        last_name: "Student",
        email: "student_test@example.com",
        password: "password",
        role: "student",
        signup_code: ENV["STUDENT_SIGNUP_CODE"] || "student_code",
        teacher: @superuser # Needs a teacher
      )

      sign_in student

      get admin_llms_url
      # Should be redirected to student root
      assert_redirected_to student_root_path
    end
  end
end
