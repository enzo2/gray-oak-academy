require "test_helper"

class LessonTest < ActiveSupport::TestCase
  def setup
    @student = users(:student)
  end

  test "student_access_status_for returns ok for accessible lesson" do
    accessible_lesson = Lesson.create!(
      course: courses(:one),
      title: "Published Accessible Lesson",
      approx_duration_min: 25,
      goals: "Practice foundational arithmetic fluency"
    )
    accessible_lesson.insert_at(1)
    LessonPlan.create!(
      lesson: accessible_lesson,
      content: [ { "Activity" => "Complete guided arithmetic practice." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    assert_equal :ok, accessible_lesson.student_access_status_for(@student)
    assert accessible_lesson.student_access_allowed?(@student)
  end

  test "student_access_status_for returns not_enrolled before wrong_teacher for another teacher lesson" do
    assert_equal :not_enrolled, lessons(:two).student_access_status_for(@student)
  end

  test "student_access_status_for returns wrong_teacher after enrollment and progress checks" do
    course = Course.create!(
      teacher: users(:admin2),
      title: "Other Teacher Course",
      summary: "Course used to verify wrong teacher status precedence.",
      grade_level: "1",
      outline: [],
      status: "active"
    )
    Enrollment.create!(student: @student, course: course)

    lesson = Lesson.create!(
      course: course,
      title: "Other Teacher Published Lesson",
      approx_duration_min: 20,
      goals: "Practice arithmetic from an alternate instruction set"
    )
    lesson.insert_at(1)
    LessonPlan.create!(
      lesson: lesson,
      content: [ { "Activity" => "Solve arithmetic practice items." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    assert_equal :wrong_teacher, lesson.student_access_status_for(@student)
  end

  test "student_access_status_for returns missing_lesson_plan after early checks pass" do
    course = Course.create!(
      teacher: users(:admin),
      title: "Missing Plan Course",
      summary: "Course used to verify missing lesson plan status precedence.",
      grade_level: "1",
      outline: [],
      status: "active"
    )
    Enrollment.create!(student: @student, course: course)

    lesson_without_plan = Lesson.create!(
      course: course,
      title: "No Plan Lesson",
      approx_duration_min: 20,
      goals: "Practice foundational arithmetic"
    )
    lesson_without_plan.insert_at(1)
    published_later_lesson = Lesson.create!(
      course: course,
      title: "Published Later Lesson",
      approx_duration_min: 20,
      goals: "Practice arithmetic with guided explanations"
    )
    published_later_lesson.insert_at(2)
    LessonPlan.create!(
      lesson: published_later_lesson,
      content: [ { "Activity" => "Complete guided arithmetic practice." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    assert_equal :missing_lesson_plan, lesson_without_plan.student_access_status_for(@student)
  end

  test "student_access_status_for returns unpublished_lesson when draft lesson passes early checks" do
    course = Course.create!(
      teacher: users(:admin),
      title: "Draft Access Course",
      summary: "Course used to verify unpublished lesson status precedence.",
      grade_level: "1",
      outline: [],
      status: "active"
    )
    Enrollment.create!(student: @student, course: course)

    draft_lesson = Lesson.create!(
      course: course,
      title: "Draft Lesson",
      approx_duration_min: 20,
      goals: "Practice arithmetic fluency with mixed operations"
    )
    draft_lesson.insert_at(1)
    LessonPlan.create!(
      lesson: draft_lesson,
      content: {},
      status: "draft",
      chalkboard_enabled: true,
      audio: "enabled"
    )
    published_later_lesson = Lesson.create!(
      course: course,
      title: "Published Later Lesson",
      approx_duration_min: 20,
      goals: "Practice arithmetic with guided explanations"
    )
    published_later_lesson.insert_at(2)
    LessonPlan.create!(
      lesson: published_later_lesson,
      content: [ { "Activity" => "Complete guided arithmetic practice." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    assert_equal :unpublished_lesson, draft_lesson.student_access_status_for(@student)
  end

  test "student_access_status_for returns not_enrolled when student has teacher but no enrollment" do
    student_without_enrollment = users(:student2)
    student_without_enrollment.update!(teacher: users(:admin))

    assert_equal :not_enrolled, lessons(:one).student_access_status_for(student_without_enrollment)
  end

  test "student_access_status_for returns ahead_of_progress when lesson is after next incomplete lesson" do
    next_lesson = Lesson.create!(
      course: courses(:one),
      title: "Next Published Lesson",
      approx_duration_min: 20,
      goals: "Practice place value with guided examples"
    )
    next_lesson.insert_at(2)
    LessonPlan.create!(
      lesson: next_lesson,
      content: [ { "Activity" => "Solve place value practice items." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    future_lesson = Lesson.create!(
      course: courses(:one),
      title: "Future Lesson",
      approx_duration_min: 20,
      goals: "Apply arithmetic reasoning to multi-step challenges"
    )
    future_lesson.insert_at(4)
    LessonPlan.create!(
      lesson: future_lesson,
      content: [ { "Activity" => "Solve multi-step challenge problems." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    assert_equal :ahead_of_progress, future_lesson.student_access_status_for(@student)
    assert_not future_lesson.student_access_allowed?(@student)
  end
end
