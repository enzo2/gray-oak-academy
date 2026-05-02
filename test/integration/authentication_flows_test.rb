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
    assert_select "[data-testid='teacher-guide-nav-link-desktop']", text: "Guide"
    assert_select "[data-testid='teacher-guide-nav-link-mobile']", text: "Guide"
  end

  test "student can sign in and access student dashboard" do
    sign_in(@student)
    get student_root_path
    assert_response :success
    assert_match /Student|Dashboard/i, response.body
    assert_select "[data-testid='teacher-guide-nav-link-desktop']", count: 0
    assert_select "[data-testid='teacher-guide-nav-link-mobile']", count: 0
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

  test "teacher account deletion releases adopted students and signs out" do
    teacher = User.create!(
      first_name: "Delete",
      last_name: "Me",
      email: "delete-flow-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: "admin",
      signup_code: ENV["TEACHER_SIGNUP_CODE"]
    )
    student = users(:student2)
    student.update!(teacher: teacher)

    sign_in(teacher)

    assert_difference("User.count", -1) do
      delete user_registration_path
    end

    assert_response :see_other
    assert_redirected_to new_user_session_path
    assert_nil student.reload.teacher_id
  end

  test "transfer assets moves resource applet ownership to target teacher" do
    source_teacher = User.create!(
      first_name: "Source",
      last_name: "Teacher",
      email: "source-teacher-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: "admin",
      signup_code: ENV["TEACHER_SIGNUP_CODE"]
    )
    target_teacher = User.create!(
      first_name: "Target",
      last_name: "Teacher",
      email: "target-teacher-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: "admin",
      signup_code: ENV["TEACHER_SIGNUP_CODE"]
    )
    resource_applet = Applet.create!(title: "Linked", code: "console.log('linked')", user: source_teacher)
    resource = Resource.create!(teacher: source_teacher, category: "Applet", description: "Linked resource", applet: resource_applet)

    sign_in(source_teacher)

    post transfer_user_assets_path, params: { target_user_id: target_teacher.id }

    assert_response :redirect
    assert_redirected_to edit_user_registration_path(active_tab: :account)
    assert_equal target_teacher.id, resource.reload.teacher_id
    assert_equal target_teacher.id, resource_applet.reload.user_id
  end

  test "teacher account deletion is blocked when resource-linked applets remain" do
    teacher = User.create!(
      first_name: "Delete",
      last_name: "Blocked",
      email: "delete-blocked-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: "admin",
      signup_code: ENV["TEACHER_SIGNUP_CODE"]
    )
    resource_applet = Applet.create!(title: "Linked", code: "console.log('linked')", user: teacher)
    Resource.create!(teacher: teacher, category: "Applet", description: "Linked resource", applet: resource_applet)

    sign_in(teacher)

    assert_no_difference("User.count") do
      delete user_registration_path
    end

    assert_response :see_other
    assert_redirected_to edit_user_registration_path(active_tab: :account)
    assert_equal teacher.id, resource_applet.reload.user_id
  end
end
