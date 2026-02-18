require "test_helper"
require "securerandom"

module Admin
  class TeacherDashboardDataServiceTest < ActiveSupport::TestCase
    setup do
      @teacher = users(:admin2)
      @other_teacher = users(:admin)
      @teacher.create_setting! if @teacher.setting.nil?
      @other_teacher.create_setting! if @other_teacher.setting.nil?
      @student = create_student(teacher: @teacher, suffix: "owner")
      @other_student = create_student(teacher: @other_teacher, suffix: "other")
      @today = Date.current
    end

    test "groups pending observations by student within teacher scope" do
      Observation.create!(student: @student, content: "Needs review on fractions", status: :pending)
      Observation.create!(student: @student, content: "Needs review on reading fluency", status: :pending)
      Observation.create!(student: @other_student, content: "Other teacher pending", status: :pending)

      dashboard = TeacherDashboardDataService.call(teacher: @teacher, today: @today)

      assert_equal 2, dashboard[:pending_observations_total]
      assert_equal 1, dashboard[:students_with_pending_observations].size
      summary = dashboard[:students_with_pending_observations].first
      assert_equal @student.id, summary[:student_id]
      assert_equal 2, summary[:pending_count]
    end

    test "returns only enrollments that are truly awaiting lessons" do
      waiting_course = create_course(teacher: @teacher, title: "Waiting Course")
      create_lesson_with_plan(course: waiting_course, title: "Draft only", plan_status: :draft)
      waiting_enrollment = Enrollment.create!(student: @student, course: waiting_course)

      available_course = create_course(teacher: @teacher, title: "Available Course")
      create_lesson_with_plan(course: available_course, title: "Published next", plan_status: :published)
      available_enrollment = Enrollment.create!(student: @student, course: available_course)

      blocked_course = create_course(teacher: @teacher, title: "Blocked Course")
      blocked_next_lesson = create_lesson_with_plan(course: blocked_course, title: "Draft next", plan_status: :draft)
      blocked_next_lesson.insert_at(1)
      blocked_later_lesson = create_lesson_with_plan(course: blocked_course, title: "Published later", plan_status: :published)
      blocked_later_lesson.insert_at(2)
      blocked_enrollment = Enrollment.create!(student: @student, course: blocked_course)

      dashboard = TeacherDashboardDataService.call(teacher: @teacher, today: @today)
      awaiting_ids = dashboard[:awaiting_lesson_enrollments].map(&:id)

      assert_includes awaiting_ids, waiting_enrollment.id
      assert_includes awaiting_ids, blocked_enrollment.id
      refute_includes awaiting_ids, available_enrollment.id
    end

    test "returns unread notification total and latest three unread items" do
      4.times do |idx|
        Notification.create!(
          recipient: @teacher,
          event_type: "conversation.context_warning",
          params: {
            "user_name" => "Student #{idx}",
            "title" => "Conversation #{idx}"
          },
          created_at: idx.minutes.ago,
          updated_at: idx.minutes.ago
        )
      end

      Notification.create!(
        recipient: @teacher,
        event_type: "conversation.context_warning",
        params: {
          "user_name" => "Read Student",
          "title" => "Read Conversation"
        },
        read_at: Time.current
      )

      dashboard = TeacherDashboardDataService.call(teacher: @teacher, today: @today)

      assert_equal 4, dashboard[:unread_notifications_total]
      assert_equal 3, dashboard[:unread_notifications].size
      assert dashboard[:unread_notifications].all? { |notification| notification.read_at.nil? }
    end

    test "aggregates and sorts recent activity across lesson completions, profiles, and feedback" do
      lesson_course = create_course(teacher: @teacher, title: "Activity Course")
      lesson = create_lesson_with_plan(course: lesson_course, title: "Activity Lesson", plan_status: :published)
      Enrollment.create!(student: @student, course: lesson_course)

      lesson_progress = LessonProgress.create!(student: @student, lesson: lesson)
      lesson_report = StudentReport.create!(
        student: @student,
        teacher: @teacher,
        reportable: lesson_progress,
        author_type: :ai_generated,
        status: :completed,
        progress_data: { "summary" => "Great session" }
      )
      lesson_progress.update_columns(completed_at: 3.hours.ago, created_at: 1.day.ago, updated_at: Time.current)
      lesson_report.update_columns(created_at: 3.hours.ago, updated_at: Time.current)

      profile_report = StudentReport.create!(
        student: @student,
        teacher: @teacher,
        reportable: @student,
        author_type: :ai_generated,
        status: :completed,
        progress_data: { "current_snapshot" => "Strong momentum this week" },
        created_at: 2.hours.ago,
        updated_at: 2.hours.ago
      )

      feedback = StudentFeedback.create!(
        student: @student,
        lesson_progress: lesson_progress,
        content: "I liked this lesson a lot!",
        created_at: 1.hour.ago,
        updated_at: 1.hour.ago
      )

      # Other teacher data should not appear.
      other_course = create_course(teacher: @other_teacher, title: "Other Activity Course")
      other_lesson = create_lesson_with_plan(course: other_course, title: "Other Lesson", plan_status: :published)
      Enrollment.create!(student: @other_student, course: other_course)
      other_progress = LessonProgress.create!(student: @other_student, lesson: other_lesson)
      StudentReport.create!(
        student: @other_student,
        teacher: @other_teacher,
        reportable: other_progress,
        author_type: :ai_generated,
        status: :completed,
        progress_data: { "summary" => "Other teacher data" },
        created_at: 30.minutes.ago,
        updated_at: 30.minutes.ago
      )

      dashboard = TeacherDashboardDataService.call(teacher: @teacher, today: @today)
      kinds = dashboard[:recent_activity_items].map { |item| item[:kind] }

      assert_includes kinds, :lesson_completed
      assert_includes kinds, :profile_generated
      assert_includes kinds, :student_feedback
      assert_equal :student_feedback, dashboard[:recent_activity_items].first[:kind]

      paths = dashboard[:recent_activity_items].map { |item| item[:path] }
      assert paths.all? { |path| path.include?("/admin/students/#{@student.id}") }

      assert profile_report.present?
      assert feedback.present?
      assert lesson_report.present?
    end

    test "returns a seven-day activity overview with started and completed counts" do
      started_course = create_course(teacher: @teacher, title: "Started Course")
      started_lesson = create_lesson_with_plan(course: started_course, title: "Started Lesson", plan_status: :published)
      started_progress = LessonProgress.create!(student: @student, lesson: started_lesson)
      started_time = (@today - 3.days).in_time_zone.change(hour: 10)
      started_progress.update_columns(created_at: started_time, updated_at: started_time)

      completed_course = create_course(teacher: @teacher, title: "Completed Course")
      completed_lesson = create_lesson_with_plan(course: completed_course, title: "Completed Lesson", plan_status: :published)
      Enrollment.create!(student: @student, course: completed_course)
      completed_progress = LessonProgress.create!(student: @student, lesson: completed_lesson)
      completed_report = StudentReport.create!(
        student: @student,
        teacher: @teacher,
        reportable: completed_progress,
        author_type: :ai_generated,
        status: :completed,
        progress_data: { "summary" => "Completed" }
      )
      completed_time = (@today - 2.days).in_time_zone.change(hour: 11)
      completed_progress.update_columns(created_at: completed_time - 1.hour, completed_at: completed_time, updated_at: completed_time)
      completed_report.update_columns(created_at: completed_time, updated_at: completed_time)

      dashboard = TeacherDashboardDataService.call(teacher: @teacher, today: @today)
      overview = dashboard[:lesson_activity_7d]

      assert_equal 7, overview.size

      by_date = overview.index_by { |entry| entry[:date] }
      assert_equal 1, by_date[@today - 3.days][:started_count]
      assert_equal 1, by_date[@today - 2.days][:completed_count]
      assert_operator dashboard[:lesson_activity_max_count], :>=, 1
    end

    private

    def create_student(teacher:, suffix:)
      User.create!(
        first_name: "Student",
        last_name: suffix.capitalize,
        email: "student-#{suffix}-#{SecureRandom.hex(4)}@example.com",
        password: "password",
        password_confirmation: "password",
        role: :student,
        signup_code: ENV.fetch("STUDENT_SIGNUP_CODE"),
        teacher: teacher
      )
    end

    def create_course(teacher:, title:, status: :active)
      Course.create!(
        teacher: teacher,
        title: title,
        summary: "A sufficiently long course summary for tests.",
        grade_level: "1",
        outline: [],
        status: status
      )
    end

    def create_lesson_with_plan(course:, title:, plan_status:)
      content = plan_status.to_s == "published" ? [ { "Activity" => "Practice examples" } ] : {}

      lesson = Lesson.create!(
        course: course,
        title: title,
        approx_duration_min: 30,
        goals: "Practice with deliberate examples and checks"
      )

      LessonPlan.create!(
        lesson: lesson,
        content: content,
        status: plan_status,
        chalkboard_enabled: true,
        audio: "enabled"
      )

      lesson
    end
  end
end
