module Admin
  class TeacherDashboardDataService
    PENDING_OBSERVATION_STUDENT_LIMIT = 8
    AWAITING_LESSONS_LIMIT = 10
    UNREAD_NOTIFICATIONS_LIMIT = 3
    RECENT_ACTIVITY_LIMIT = 12
    RECENT_ACTIVITY_SOURCE_LIMIT = 20

    def self.call(teacher:, today: Time.zone.today)
      new(teacher:, today:).call
    end

    def initialize(teacher:, today:)
      @teacher = teacher
      @today = today
    end

    def call
      pending_data = pending_observations_summary
      unread_data = unread_notifications_bundle
      lesson_activity = lesson_activity_overview

      {
        today: @today,
        pending_observations_total: pending_data[:total],
        students_with_pending_observations: pending_data[:students],
        awaiting_lesson_enrollments: awaiting_lesson_enrollments,
        unread_notifications_total: unread_data[:total],
        unread_notifications: unread_data[:items],
        recent_activity_items: recent_activity_items,
        lesson_activity_7d: lesson_activity,
        lesson_activity_max_count: lesson_activity.flat_map { |point| [ point[:started_count], point[:completed_count] ] }.max.to_i
      }
    end

    private

    def scoped_student_ids
      @scoped_student_ids ||= @teacher.students.select(:id)
    end

    def pending_observations_summary
      relation = Observation.pending.joins(:student).where(users: { teacher_id: @teacher.id })

      grouped_rows = relation
        .group("users.id", "users.first_name", "users.last_name")
        .select(
          "users.id AS student_id",
          "users.first_name AS student_first_name",
          "users.last_name AS student_last_name",
          "COUNT(observations.id) AS pending_count",
          "MAX(observations.created_at) AS latest_pending_at"
        )
        .order(Arel.sql("pending_count DESC, latest_pending_at DESC"))
        .limit(PENDING_OBSERVATION_STUDENT_LIMIT)

      {
        total: relation.count,
        students: grouped_rows.map do |row|
          {
            student_id: row.student_id,
            student_name: "#{row.student_first_name} #{row.student_last_name}",
            pending_count: row.pending_count.to_i,
            latest_pending_at: row.latest_pending_at
          }
        end
      }
    end

    def awaiting_lesson_enrollments
      Enrollment.awaiting_lessons_for_teacher(@teacher.id)
        .includes(:student, :course)
        .order(updated_at: :desc)
        .limit(AWAITING_LESSONS_LIMIT)
    end

    def unread_notifications_bundle
      unread = @teacher.notifications.unread.recent
      {
        total: unread.count,
        items: unread.limit(UNREAD_NOTIFICATIONS_LIMIT)
      }
    end

    def recent_activity_items
      items = lesson_completion_items + profile_report_items + feedback_items
      items.sort_by { |item| item[:occurred_at] || Time.at(0) }
           .reverse
           .first(RECENT_ACTIVITY_LIMIT)
    end

    def lesson_completion_items
      LessonProgress.completed
        .where(student_id: scoped_student_ids)
        .includes(:student, :student_report, lesson: :course)
        .order(Arel.sql("COALESCE(lesson_progresses.completed_at, student_reports.created_at) DESC"))
        .limit(RECENT_ACTIVITY_SOURCE_LIMIT)
        .map do |lesson_progress|
          lesson = lesson_progress.lesson
          course = lesson&.course
          student = lesson_progress.student
          report = lesson_progress.student_report

          {
            kind: :lesson_completed,
            occurred_at: lesson_progress.completed_at || report&.created_at || lesson_progress.created_at,
            title: "#{student.name} completed #{lesson&.title || 'a lesson'}",
            subtitle: course ? "Course: #{course.title}" : "Course unavailable",
            student: student,
            path: student_journal_path(student, report_id: report&.id)
          }
        end
    end

    def profile_report_items
      StudentReport.profile_reports
        .status_completed
        .where(student_id: scoped_student_ids)
        .includes(:student)
        .order(created_at: :desc)
        .limit(RECENT_ACTIVITY_SOURCE_LIMIT)
        .map do |report|
          snapshot = if report.progress_data.is_a?(Hash)
            report.progress_data["current_snapshot"].to_s.squish.truncate(140)
          else
            ""
          end

          {
            kind: :profile_generated,
            occurred_at: report.created_at,
            title: "Profile updated for #{report.student.name}",
            subtitle: snapshot.presence || "Student profile report generated",
            student: report.student,
            path: student_journal_path(report.student, report_id: report.id)
          }
        end
    end

    def feedback_items
      StudentFeedback.where(student_id: scoped_student_ids)
        .includes(:student, lesson_progress: { lesson: :course })
        .order(created_at: :desc)
        .limit(RECENT_ACTIVITY_SOURCE_LIMIT)
        .map do |feedback|
          lesson = feedback.lesson_progress&.lesson
          course = lesson&.course
          subtitle_prefix = if course && lesson
            "#{course.title} - #{lesson.title}"
          elsif lesson
            lesson.title
          else
            "General"
          end

          {
            kind: :student_feedback,
            occurred_at: feedback.created_at,
            title: "#{feedback.student.name} sent feedback",
            subtitle: "#{subtitle_prefix}: #{feedback.content.to_s.squish.truncate(140)}",
            student: feedback.student,
            path: student_journal_path(feedback.student)
          }
        end
    end

    def lesson_activity_overview
      start_date = @today - 6.days
      date_range = start_date.beginning_of_day..@today.end_of_day

      started_counts = LessonProgress
        .where(student_id: scoped_student_ids, created_at: date_range)
        .group(Arel.sql("DATE(lesson_progresses.created_at)"))
        .count

      completed_counts = LessonProgress.completed
        .where(student_id: scoped_student_ids)
        .where("COALESCE(lesson_progresses.completed_at, student_reports.created_at) BETWEEN ? AND ?", date_range.begin, date_range.end)
        .group(Arel.sql("DATE(COALESCE(lesson_progresses.completed_at, student_reports.created_at))"))
        .count

      started_by_date = normalize_grouped_date_counts(started_counts)
      completed_by_date = normalize_grouped_date_counts(completed_counts)

      (start_date..@today).map do |date|
        {
          date: date,
          started_count: started_by_date[date] || 0,
          completed_count: completed_by_date[date] || 0
        }
      end
    end

    def normalize_grouped_date_counts(raw_counts)
      raw_counts.each_with_object({}) do |(raw_date, count), normalized|
        normalized[raw_date.to_date] = count
      end
    end

    def student_journal_path(student, report_id: nil)
      anchor = report_id.present? ? "student_report_#{report_id}" : nil
      Rails.application.routes.url_helpers.admin_student_path(student, active_tab: "journal_timeline", anchor: anchor)
    end
  end
end
