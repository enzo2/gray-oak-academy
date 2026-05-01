class Enrollment < ApplicationRecord
  belongs_to :student, class_name: "User", inverse_of: :enrollments
  belongs_to :course
  has_many :student_reports, as: :reportable, dependent: :nullify # used for course-end reports

  # Enforce no duplicate enrollments
  validates_uniqueness_of :student_id, scope: :course_id, message: "has already enrolled in this course"

  # Scopes filter completed/in_progress based on the presence of an enrollment report
  scope :completed, -> { joins(:student_reports).where(student_reports: { status: :completed }) }
  scope :in_progress, -> { where.not(
      id: joins(:student_reports).where(student_reports: { status: :completed }).select(:id)
  )}

  # Find enrollments where the student is awaiting their next lesson, meaning they have an incomplete lesson that is not currently available to start.
  def self.awaiting_lessons_for_teacher(teacher_id)
    joins(:student, :course)
      .where(users: { teacher_id: teacher_id })
      .where(courses: { status: :active, kind: "full_course" })
      .in_progress
      # Query shape:
      # 1) Correlated subquery picks the earliest incomplete lesson in course order.
      #    A lesson is incomplete when no completed LessonProgress report exists for this student.
      # 2) That lesson is "unavailable" when it has no lesson_plan or its plan is not published.
      # 3) EXISTS(...) returns only enrollments that satisfy the unavailable-next-lesson condition.
      .where(<<~SQL.squish)
        EXISTS (
          SELECT 1
          FROM lessons AS next_lesson
          LEFT JOIN lesson_plans ON lesson_plans.lesson_id = next_lesson.id
          WHERE next_lesson.id = (
            SELECT lessons.id
            FROM lessons
            WHERE lessons.course_id = enrollments.course_id
              AND NOT EXISTS (
                SELECT 1
                FROM lesson_progresses
                INNER JOIN student_reports
                  ON student_reports.reportable_type = 'LessonProgress'
                  AND student_reports.reportable_id = lesson_progresses.id
                  AND student_reports.status = 'completed'
                WHERE lesson_progresses.lesson_id = lessons.id
                  AND lesson_progresses.student_id = enrollments.student_id
                  AND student_reports.student_id = enrollments.student_id
              )
            ORDER BY lessons.position ASC
            LIMIT 1
          )
            AND (lesson_plans.id IS NULL OR lesson_plans.status <> 'published')
        )
      SQL
  end

  # Returns the lessons completed by the student, as determined by having a student report
  # (Would not include any lessons that were completed and then deleted)
  def completed_lessons
    course.lessons
      .joins(:student_reports)
      .where(student_reports: { student_id: student.id, status: :completed })
      .order(position: :asc)
  end

  def incomplete_lessons
    course.lessons.where.not(id: completed_lessons.pluck(:id)).order(position: :asc)
  end

  # Returns the number of lessons completed by the student in the course
  def completed_lessons_count
    completed_lessons.count
  end

  # Returns the total number of lessons in the course
  def total_lessons_count
    course.lessons.count
  end

  def remaining_lessons
    incomplete_lessons.count
  end

  # Calculates the percentage of lessons completed in the course
  def progress_percentage
    return 0 if total_lessons_count.zero?
    (completed_lessons_count.to_f / total_lessons_count * 100).round
  end

  # Whether the next incomplete lesson is currently available to start.
  def has_available_lesson?
    next_available_lesson.present?
  end

  # Returns the first incomplete lesson in course order, regardless of lesson-plan state.
  def next_incomplete_lesson
    incomplete_lessons.includes(:lesson_plan).first
  end

  # Returns the first incomplete lesson only when that exact lesson has a published plan.
  # This never skips ahead to later lessons.
  def next_available_lesson
    lesson = next_incomplete_lesson
    return unless lesson&.lesson_plan&.status_published?

    lesson
  end

  # Position of the student's next incomplete lesson for access gating.
  # Returns nil when no incomplete lessons remain.
  def next_incomplete_lesson_position
    next_incomplete_lesson&.position
  end

  # Sequence-only gate for :ahead_of_progress.
  # Lesson-plan presence/publication is validated separately.
  def not_ahead_of_progress?(lesson_position)
    return false if lesson_position.blank?

    next_position = next_incomplete_lesson_position
    return completed? if next_position.nil?

    lesson_position <= next_position
  end

  # Determine if enrollment is completed by checking if all lessons have been completed
  def completed?
    return false unless course.lessons.any?
    completed_lessons_count == total_lessons_count
  end

  # When the course is completed, we need to generate a course-end summary report based on all the lesson reports.
  def course_report_check
    return if course.kind_quick_lesson?

    # If the course is completed and there are no student reports, generate a course report
    if completed? && !student_reports.exists?
      Rails.logger.info "Found missing enrollment report. Generating report for enrollment #{id}"
      GenerateCourseReportJob.perform_later(self)
    end
  end

  def lesson_history_for_prompt
    unless completed_lessons.empty?
      completed_lessons.map do |lesson|
        report = lesson.student_reports.where(student: student).first
        report_content = report.progress_data.to_s || "Report not available."
        "Lesson #{lesson.position}: #{lesson.title} | Goals: #{lesson.goals} | Student Report:#{report_content}"
      end.join("\n")
    else
      "No previous lessons completed in this course yet."
    end
  end
end
