require "test_helper"

class Admin::StudentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:admin)
    @other_teacher = users(:admin2)
    @student = users(:student)
    @other_student = users(:student2)
  end

  test "journal observations sub-tab sorts chronologically oldest first" do
    sign_in @teacher

    older = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Older timeline observation",
      status: :approved,
      relevance_weight: 1.0,
      created_at: 10.days.ago
    )
    newer = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Newer timeline observation",
      status: :approved,
      relevance_weight: 1.0,
      created_at: 1.day.ago
    )

    get admin_student_path(
      @student,
      active_tab: :journal_observations,
      observation_sort: "chron_asc"
    )

    assert_response :success
    assert_select "[data-testid='observations-management']"
    assert_select "option[value='chron_asc'][selected='selected']"

    older_index = @response.body.index("id=\"obs_mgmt_observation_#{older.id}_card_container\"")
    newer_index = @response.body.index("id=\"obs_mgmt_observation_#{newer.id}_card_container\"")

    assert_not_nil older_index
    assert_not_nil newer_index
    assert_operator older_index, :<, newer_index
  end

  test "journal observations sub-tab sorts by weight high to low" do
    sign_in @teacher

    low_confidence = Observation.create!(
      student: @student,
      author: @teacher,
      content: "Low confidence observation",
      status: :approved,
      relevance_weight: 0.2,
      created_at: 1.day.ago
    )
    high_confidence = Observation.create!(
      student: @student,
      author: @teacher,
      content: "High confidence observation",
      status: :approved,
      relevance_weight: 1.0,
      last_validated_at: Time.current,
      created_at: 1.day.ago
    )

    get admin_student_path(
      @student,
      active_tab: :journal_observations,
      observation_sort: "weight_desc"
    )

    assert_response :success
    assert_select "option[value='weight_desc'][selected='selected']"

    high_index = @response.body.index("id=\"obs_mgmt_observation_#{high_confidence.id}_card_container\"")
    low_index = @response.body.index("id=\"obs_mgmt_observation_#{low_confidence.id}_card_container\"")

    assert_not_nil high_index
    assert_not_nil low_index
    assert_operator high_index, :<, low_index
  end

  test "adopt sets flash error when attempting to adopt self (validate_not_own_teacher)" do
    sign_in @teacher

    assert_equal @teacher, @teacher.teacher

    post adopt_admin_student_path(@teacher.id)

    assert_response :unprocessable_content
    assert_equal admin_students_url, response.location
    assert flash[:error].present?, "Expected flash error to be set"
    assert_match(/cannot be yourself/i, flash[:error])
    assert_nil @teacher.reload.teacher_id
  end

  test "cannot view show page of another teacher's student" do
    sign_in @teacher
    @other_student.update!(teacher: @other_teacher)

    get admin_student_path(@other_student)
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "cannot view show page of unadopted student as non-superuser teacher" do
    @other_student.update!(teacher: nil)
    sign_in @teacher

    get admin_student_path(@other_student)

    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "cannot view journal of unadopted student as non-superuser teacher" do
    @other_student.update!(teacher: nil)
    sign_in @teacher

    get journal_admin_student_path(@other_student), as: :turbo_stream

    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "superuser can view show page and journal for unadopted student" do
    superuser = users(:super_user)
    @other_student.update!(teacher: nil)
    sign_in superuser

    get admin_student_path(@other_student)
    assert_response :success

    get journal_admin_student_path(@other_student), as: :turbo_stream
    assert_response :success
  end

  test "cannot enroll another teacher's student" do
    sign_in @teacher
    @other_student.update!(teacher: @other_teacher)

    post enroll_admin_student_path(@other_student), params: { course_id: courses(:one).id }
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "cannot enroll own student in another teacher's course" do
    sign_in @teacher

    assert_no_difference("Enrollment.count") do
      post enroll_admin_student_path(@student), params: { course_id: courses(:two).id }
    end

    assert_response :not_found
  end

  test "cannot unenroll another teacher's student" do
    sign_in @teacher
    @other_student.update!(teacher: @other_teacher)

    delete unenroll_admin_student_path(@other_student), params: { course_id: courses(:two).id }
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end
end
