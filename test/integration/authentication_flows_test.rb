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

  test "student dashboard renders assigned quick lessons separately" do
    quick_lesson = @teacher.taught_courses.create!(
      kind: "quick_lesson",
      title: "Quick Fractions",
      summary: "A quick one-off lesson about common denominators.",
      grade_level: "5"
    )
    quick_lesson.lessons.create!(
      title: "Quick Fractions",
      goals: "Understand common denominators using shared units.",
      approx_duration_min: 20
    )
    quick_lesson.enrollments.create!(student: @student)

    sign_in(@student)
    get student_root_path(active_tab: :quick_lessons)

    assert_response :success
    assert_select "#quick_lessons", text: /Quick Fractions/
    assert_select "#courses", text: /Quick Fractions/, count: 0
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

  test "turbo logout redirects immediately to the login page" do
    sign_in(@teacher)

    delete destroy_user_session_path, as: :turbo_stream

    assert_response :see_other
    assert_redirected_to new_user_session_path

    follow_redirect!

    assert_response :success
    assert_match(/Log in/i, response.body)
  end
end
