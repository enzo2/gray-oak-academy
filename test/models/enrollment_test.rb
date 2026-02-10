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
end
