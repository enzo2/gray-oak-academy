require "test_helper"

class Admin::StudentsControllerTest < ActionDispatch::IntegrationTest
  test "journal observations sub-tab sorts chronologically oldest first" do
    teacher = users(:admin)
    student = users(:student)
    sign_in teacher

    older = Observation.create!(
      student: student,
      author: teacher,
      content: "Older timeline observation",
      status: :approved,
      relevance_weight: 1.0,
      created_at: 10.days.ago
    )
    newer = Observation.create!(
      student: student,
      author: teacher,
      content: "Newer timeline observation",
      status: :approved,
      relevance_weight: 1.0,
      created_at: 1.day.ago
    )

    get admin_student_path(
      student,
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
    teacher = users(:admin)
    student = users(:student)
    sign_in teacher

    low_confidence = Observation.create!(
      student: student,
      author: teacher,
      content: "Low confidence observation",
      status: :approved,
      relevance_weight: 0.2,
      created_at: 1.day.ago
    )
    high_confidence = Observation.create!(
      student: student,
      author: teacher,
      content: "High confidence observation",
      status: :approved,
      relevance_weight: 1.0,
      last_validated_at: Time.current,
      created_at: 1.day.ago
    )

    get admin_student_path(
      student,
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
    admin = users(:admin)
    sign_in admin

    # Sanity: admin shouldn't already have a teacher
    assert_equal admin, admin.teacher

    post adopt_admin_student_path(admin.id)

    # Controller redirects with 422 on failure
    assert_response :unprocessable_content
    assert_equal admin_students_url, response.location

    # Flash should surface the model validation message
    assert flash[:error].present?, "Expected flash error to be set"
    assert_match(/cannot be yourself/i, flash[:error])

    # No change persisted
    assert_nil admin.reload.teacher_id
  end

  test "cannot view show page of another teacher's student" do
    teacher = users(:admin)
    other_student = users(:student2) # Belongs to admin2 or no one? Fixture says student2 has NO teacher or admin2?
    # Let's check fixture users.yml in my head/context
    # student2: teacher: nil? No, fixture says:
    # student2: ... teacher: nil (based on earlier dump, wait)
    # student2 fixture in dump:
    # student2:
    #   ...
    #   teacher: admin # Wait, student has teacher: admin.
    #   student2 has ... wait let me check the file content again.

    # In repomix-output.xml:
    # student: teacher: admin
    # student2: teacher: nil (implied? No, let's look at users.yml in dump)
    # student2: ... no teacher line.

    # So student2 has no teacher.
    # admin2 exists.

    sign_in teacher

    # Assign student2 to admin2
    other_teacher = users(:admin2)
    other_student.update!(teacher: other_teacher)

    get admin_student_path(other_student)
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "cannot view show page of unadopted student as non-superuser teacher" do
    teacher = users(:admin)
    unadopted_student = users(:student2)
    unadopted_student.update!(teacher: nil)
    sign_in teacher

    get admin_student_path(unadopted_student)

    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "cannot view journal of unadopted student as non-superuser teacher" do
    teacher = users(:admin)
    unadopted_student = users(:student2)
    unadopted_student.update!(teacher: nil)
    sign_in teacher

    get journal_admin_student_path(unadopted_student), as: :turbo_stream

    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "superuser can view show page and journal for unadopted student" do
    superuser = users(:super_user)
    unadopted_student = users(:student2)
    unadopted_student.update!(teacher: nil)
    sign_in superuser

    get admin_student_path(unadopted_student)
    assert_response :success

    get journal_admin_student_path(unadopted_student), as: :turbo_stream
    assert_response :success
  end

  test "non-superuser teacher sees other student name without dashboard link" do
    teacher = users(:admin)
    other_student = users(:student2)
    sign_in teacher

    get admin_students_path

    assert_response :success
    assert_select "#other-students-content", text: other_student.name
    assert_select "#other-students-content a[href='#{admin_student_path(other_student)}']", count: 0
  end

  test "cannot enroll another teacher's student" do
    teacher = users(:admin)
    sign_in teacher

    other_teacher = users(:admin2)
    other_student = users(:student2)
    other_student.update!(teacher: other_teacher)

    course = courses(:one) # teacher's course

    post enroll_admin_student_path(other_student), params: { course_id: course.id }
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end

  test "cannot unenroll another teacher's student" do
    teacher = users(:admin)
    sign_in teacher

    other_teacher = users(:admin2)
    other_student = users(:student2)
    other_student.update!(teacher: other_teacher)

    # Student2 is already enrolled in course two (admin2's course) from fixtures
    course = courses(:two)

    delete unenroll_admin_student_path(other_student), params: { course_id: course.id }
    assert_redirected_to admin_students_path
    assert_equal "You are not that student's teacher.", flash[:warning]
  end
end
