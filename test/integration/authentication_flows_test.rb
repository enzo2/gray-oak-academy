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
end
