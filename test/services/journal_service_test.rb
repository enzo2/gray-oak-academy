require "test_helper"

class JournalServiceTest < ActiveSupport::TestCase
  def setup
    @student = users(:student)
    @teacher = users(:admin)
    @student.update!(teacher: @teacher)

    # Clean up existing records for the student to ensure deterministic counts
    @student.observations.destroy_all
    @student.student_feedbacks.destroy_all
    @student.memories.destroy_all
    @student.student_reports.destroy_all

    # Create one of each record type with distinct created_at times
    @time_base = Time.current

    @observation = Observation.create!(
      student: @student,
      content: "Obs 1",
      status: :approved,
      created_at: @time_base - 4.hours
    )

    @feedback = StudentFeedback.create!(
      student: @student,
      content: "Feedback 1",
      created_at: @time_base - 3.hours
    )

    @report = StudentReport.create!(
      student: @student,
      reportable_type: "User", # Generic report
      reportable_id: @student.id,
      author_type: :ai_generated,
      status: :completed,
      progress_data: { summary: "Report 1" },
      created_at: @time_base - 2.hours
    )

    @memory = Memory.create!(
      student: @student,
      body: "Memory 1",
      created_at: @time_base - 1.hour
    )
  end

  test "get_timeline returns aggregated records sorted by created_at desc" do
    timeline = JournalService.get_timeline(@student)

    assert_equal 4, timeline.size

    # Expected order: Memory (newest), Report, Feedback, Observation (oldest)
    assert_equal @memory, timeline[0]
    assert_equal @report, timeline[1]
    assert_equal @feedback, timeline[2]
    assert_equal @observation, timeline[3]
  end

  test "get_timeline filters out pending observations for teacher_mode=false" do
    pending_obs = Observation.create!(
      student: @student,
      content: "Pending Obs",
      status: :pending,
      created_at: @time_base
    )

    timeline = JournalService.get_timeline(@student, teacher_mode: false)
    assert_not_includes timeline, pending_obs
  end

  test "get_timeline includes rejected observations for teacher_mode=true" do
    rejected_obs = Observation.create!(
      student: @student,
      content: "Rejected Obs",
      status: :rejected,
      created_at: @time_base
    )

    timeline = JournalService.get_timeline(@student, teacher_mode: true)
    assert_includes timeline, rejected_obs

    # Verify student cannot see it
    student_timeline = JournalService.get_timeline(@student, teacher_mode: false)
    assert_not_includes student_timeline, rejected_obs
  end

  test "get_timeline supports pagination" do
    # Create extra records to force pagination
    # We already have 4. Let's ask for page 1 with per_page 2.

    page1 = JournalService.get_timeline(@student, page: 1, per_page: 2)
    assert_equal 2, page1.size
    assert_equal @memory, page1[0]
    assert_equal @report, page1[1]

    page2 = JournalService.get_timeline(@student, page: 2, per_page: 2)
    assert_equal 2, page2.size
    assert_equal @feedback, page2[0]
    assert_equal @observation, page2[1]
  end
end
