require "test_helper"

class EnrollmentTest < ActiveSupport::TestCase
  def setup
    @enrollment = enrollments(:one)
    @student = users(:student)
    @course = courses(:one)
  end

  test "should be valid with valid attributes" do
    assert @enrollment.valid?
  end

  test "completed_lessons returns correct lessons" do
    # No completed lessons in fixture, so should be empty
    assert_equal [], @enrollment.completed_lessons
  end

  test "incomplete_lessons returns all lessons if none completed" do
    assert_equal @course.lessons.sort_by(&:position), @enrollment.incomplete_lessons.sort_by(&:position)
  end

  test "progress_percentage is 0 if no lessons completed" do
    assert_equal 0, @enrollment.progress_percentage
  end

  test "total_lessons_count returns correct count" do
    assert_equal @course.lessons.count, @enrollment.total_lessons_count
  end

  test "completed? returns false if not all lessons completed" do
    assert_not @enrollment.completed?
  end

  test "next_incomplete_lesson_position returns nil when there are no published incomplete lessons" do
    assert_nil @enrollment.next_incomplete_lesson_position
  end

  test "next_incomplete_lesson_position prefers published incomplete lessons" do
    course = Course.create!(
      teacher: users(:admin),
      title: "Published Gate Course",
      summary: "Course for enrollment access gating checks.",
      grade_level: "1",
      outline: [],
      status: "active"
    )
    enrollment = Enrollment.create!(student: users(:student), course: course)

    draft_lesson = Lesson.create!(
      course: course,
      title: "Draft Gate Lesson",
      approx_duration_min: 20,
      goals: "Practice arithmetic with visual aids"
    )
    draft_lesson.insert_at(1)
    LessonPlan.create!(lesson: draft_lesson, content: {}, status: "draft", chalkboard_enabled: true, audio: "enabled")

    published_lesson = Lesson.create!(
      course: course,
      title: "Published Gate Lesson",
      approx_duration_min: 20,
      goals: "Practice arithmetic with worked examples"
    )
    published_lesson.insert_at(2)
    LessonPlan.create!(
      lesson: published_lesson,
      content: [ { "Activity" => "Solve mixed arithmetic problems." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    assert_equal published_lesson.position, enrollment.next_incomplete_lesson_position
    assert enrollment.allows_lesson_position?(published_lesson.position)
  end

  test "allows_lesson_position? returns false when no published lessons are available" do
    assert_not @enrollment.allows_lesson_position?(1)
  end

  test "allows_lesson_position? permits next lesson or earlier and blocks later lessons" do
    course = Course.create!(
      teacher: users(:admin),
      title: "Progress Gate Course",
      summary: "Course for lesson progression access checks.",
      grade_level: "1",
      outline: [],
      status: "active"
    )
    enrollment = Enrollment.create!(student: users(:student), course: course)

    first_published = Lesson.create!(
      course: course,
      title: "Published Lesson A",
      approx_duration_min: 20,
      goals: "Practice arithmetic fluency in context"
    )
    first_published.insert_at(1)
    LessonPlan.create!(
      lesson: first_published,
      content: [ { "Warmup" => "Solve five mixed arithmetic questions." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    second_published = Lesson.create!(
      course: course,
      title: "Published Lesson B",
      approx_duration_min: 20,
      goals: "Apply arithmetic to two-step story problems"
    )
    second_published.insert_at(2)
    LessonPlan.create!(
      lesson: second_published,
      content: [ { "Practice" => "Solve two-step story problems." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    next_position = enrollment.next_incomplete_lesson_position
    assert next_position.present?

    assert enrollment.allows_lesson_position?(next_position)
    assert_not enrollment.allows_lesson_position?(next_position + 1)
  end

  test "allows_lesson_position? returns false for blank lesson position" do
    assert_not @enrollment.allows_lesson_position?(nil)
  end

  test "awaiting_lessons_for_teacher returns only active in-progress enrollments without published incomplete lessons" do
    teacher = users(:admin)
    other_teacher = users(:admin2)
    student = users(:student)
    other_student = users(:student2)
    other_student.update!(teacher: other_teacher)

    waiting_course = Course.create!(
      teacher: teacher,
      title: "Waiting Enrollment Course",
      summary: "Waiting course summary with sufficient length.",
      grade_level: "1",
      outline: [],
      status: :active
    )
    waiting_lesson = Lesson.create!(
      course: waiting_course,
      title: "Waiting Draft Lesson",
      approx_duration_min: 20,
      goals: "Practice with guided examples and checks"
    )
    LessonPlan.create!(lesson: waiting_lesson, content: {}, status: :draft, chalkboard_enabled: true, audio: "enabled")
    waiting_enrollment = Enrollment.create!(student: student, course: waiting_course)

    available_course = Course.create!(
      teacher: teacher,
      title: "Available Enrollment Course",
      summary: "Available course summary with sufficient length.",
      grade_level: "1",
      outline: [],
      status: :active
    )
    available_lesson = Lesson.create!(
      course: available_course,
      title: "Published Available Lesson",
      approx_duration_min: 20,
      goals: "Practice with guided examples and checks"
    )
    LessonPlan.create!(
      lesson: available_lesson,
      content: [ { "Activity" => "Practice published lesson content" } ],
      status: :published,
      chalkboard_enabled: true,
      audio: "enabled"
    )
    available_enrollment = Enrollment.create!(student: student, course: available_course)

    completed_course = Course.create!(
      teacher: teacher,
      title: "Completed Enrollment Course",
      summary: "Completed course summary with sufficient length.",
      grade_level: "1",
      outline: [],
      status: :active
    )
    completed_lesson = Lesson.create!(
      course: completed_course,
      title: "Completed Draft Lesson",
      approx_duration_min: 20,
      goals: "Practice with guided examples and checks"
    )
    LessonPlan.create!(lesson: completed_lesson, content: {}, status: :draft, chalkboard_enabled: true, audio: "enabled")
    completed_enrollment = Enrollment.create!(student: student, course: completed_course)
    StudentReport.create!(
      student: student,
      teacher: teacher,
      reportable: completed_enrollment,
      author_type: :teacher_written,
      status: :completed,
      progress_data: { "summary" => "Course completed" }
    )

    archived_course = Course.create!(
      teacher: teacher,
      title: "Archived Enrollment Course",
      summary: "Archived course summary with sufficient length.",
      grade_level: "1",
      outline: [],
      status: :archived
    )
    archived_lesson = Lesson.create!(
      course: archived_course,
      title: "Archived Draft Lesson",
      approx_duration_min: 20,
      goals: "Practice with guided examples and checks"
    )
    LessonPlan.create!(lesson: archived_lesson, content: {}, status: :draft, chalkboard_enabled: true, audio: "enabled")
    archived_enrollment = Enrollment.create!(student: student, course: archived_course)

    other_teacher_course = Course.create!(
      teacher: other_teacher,
      title: "Other Teacher Course",
      summary: "Other teacher course summary with sufficient length.",
      grade_level: "1",
      outline: [],
      status: :active
    )
    other_teacher_lesson = Lesson.create!(
      course: other_teacher_course,
      title: "Other Teacher Draft Lesson",
      approx_duration_min: 20,
      goals: "Practice with guided examples and checks"
    )
    LessonPlan.create!(lesson: other_teacher_lesson, content: {}, status: :draft, chalkboard_enabled: true, audio: "enabled")
    other_teacher_enrollment = Enrollment.create!(student: other_student, course: other_teacher_course)

    results = Enrollment.awaiting_lessons_for_teacher(teacher.id)

    assert_includes results, waiting_enrollment
    assert_not_includes results, available_enrollment
    assert_not_includes results, completed_enrollment
    assert_not_includes results, archived_enrollment
    assert_not_includes results, other_teacher_enrollment
  end
end
