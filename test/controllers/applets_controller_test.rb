require "test_helper"

class AppletsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @teacher = users(:admin)
    @other_teacher = users(:admin2)
    @student = users(:student)
    @orphaned_student = users(:student2)
    @superuser = users(:super_user)

    @teacher_applet = Applet.create!(title: "Teacher Applet", code: "console.log('t');", user: @teacher)
    @other_teacher_applet = Applet.create!(title: "Other Teacher Applet", code: "console.log('ot');", user: @other_teacher)
    @student_applet = Applet.create!(title: "Student Applet", code: "console.log('s');", user: @student)
    @orphaned_applet = Applet.create!(title: "Orphaned Applet", code: "console.log('o');", user: @orphaned_student)
    @superuser_applet = Applet.create!(title: "Superuser Applet", code: "console.log('su');", user: @superuser)
  end

  test "student with teacher can access own and teacher applets" do
    sign_in @student

    get applet_path(@student_applet)
    assert_response :success

    get applet_path(@teacher_applet)
    assert_response :success
  end

  test "student with teacher cannot access other teacher applets" do
    sign_in @student

    get applet_path(@other_teacher_applet)
    assert_response :not_found
  end

  test "orphaned student can access own applet only" do
    sign_in @orphaned_student

    get applet_path(@orphaned_applet)
    assert_response :success

    get applet_path(@teacher_applet)
    assert_response :not_found
  end

  test "admin can access own and students applets" do
    sign_in @teacher

    get applet_path(@teacher_applet)
    assert_response :success

    get applet_path(@student_applet)
    assert_response :success
  end

  test "admin cannot access other teacher applets" do
    sign_in @teacher

    get applet_path(@other_teacher_applet)
    assert_response :not_found
  end

  test "superuser can access any applet" do
    sign_in @superuser

    get applet_path(@other_teacher_applet)
    assert_response :success

    get applet_path(@student_applet)
    assert_response :success
  end

  test "index includes preview link for applets without resources" do
    sign_in @teacher

    get applets_path

    assert_response :success
    assert_select "a[href='#{run_applet_path(@teacher_applet)}'][target='_blank'][rel='noopener noreferrer']" do
      assert_select "sl-button", text: /Preview/
      assert_select "sl-icon[name='play-circle']"
    end
  end

  test "student cannot delete teacher applet" do
    sign_in @student

    assert_no_difference("Applet.count") do
      delete applet_path(@teacher_applet), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :not_found
  end

  test "student can delete own applet" do
    sign_in @student

    assert_difference("Applet.count", -1) do
      delete applet_path(@student_applet), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  test "student cannot delete own applet when it belongs to a resource" do
    resource = Resource.create!(teacher: @teacher, category: "Applet", applet: @student_applet)
    @student_applet.reload
    assert_equal resource.id, @student_applet.resource_id

    sign_in @student

    assert_no_difference("Applet.count") do
      delete applet_path(@student_applet), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :not_found
  end

  test "teacher is warned when deleting applet linked to resource" do
    resource = Resource.create!(teacher: @teacher, category: "Applet", applet: @student_applet)
    @student_applet.reload
    assert_equal resource.id, @student_applet.resource_id

    sign_in @teacher

    assert_no_difference("Applet.count") do
      delete applet_path(@student_applet), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :unprocessable_content
  end

  test "student cannot save applet as resource" do
    sign_in @student

    assert_no_difference("Resource.count") do
      post save_as_resource_applet_path(@student_applet)
    end
    assert_response :not_found
  end

  test "run renders preview metadata for standalone applet page" do
    sign_in @teacher

    get run_applet_path(@teacher_applet)

    assert_response :success
    assert_select "title", text: /Teacher Applet Preview/
    assert_select "link[rel='icon'][href*='logo_icon_negative']"
    assert_select "meta[name='viewport'][content='width=device-width,initial-scale=1']"
  end

  test "run renders dark preview shell when requested by chalkboard" do
    sign_in @teacher

    get run_applet_path(@teacher_applet, theme: "dark")

    assert_response :success
    assert_select "html.dark"
  end
end
