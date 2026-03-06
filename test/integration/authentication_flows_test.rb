require "test_helper"

class AuthenticationFlowsTest < ActionDispatch::IntegrationTest
  def setup
    @teacher = users(:admin)
    @student = users(:student)
  end

  test "teacher can sign in and access teacher dashboard" do
    sign_in(@teacher)
    get admin_root_path
    assert_response :success
    assert_match /Teacher|Dashboard/i, response.body
  end

  test "student can sign in and access student dashboard" do
    sign_in(@student)
    get student_root_path
    assert_response :success
    assert_match /Student|Dashboard/i, response.body
  end

  test "unauthenticated user is redirected from dashboard" do
    get admin_root_path
    assert_response :redirect
    follow_redirect!
    assert_match /Log in/i, response.body
  end

  test "signup rejects superuser role submission" do
    ENV["ALLOW_SIGNUPS"] = "true"

    assert_no_difference("User.count") do
      post user_registration_path, params: {
        user: {
          first_name: "Bad",
          last_name: "Role",
          email: "badrole@example.com",
          password: "password",
          password_confirmation: "password",
          role: "superuser",
          signup_code: ENV["TEACHER_SIGNUP_CODE"]
        }
      }
    end

    assert_response :unprocessable_content
    assert_match(/must be student or admin during sign up/i, response.body)
  ensure
    ENV["ALLOW_SIGNUPS"] = nil
  end

  test "settings memories tab renders labeled memory action buttons" do
    sign_in(@student)

    get edit_user_registration_path(active_tab: :memories)

    assert_response :success
    assert_select "button[aria-label='Edit memory'][title='Edit memory']", count: 2
    assert_select "button[aria-label='Delete memory'][title='Delete memory']", count: 2
  end
end
