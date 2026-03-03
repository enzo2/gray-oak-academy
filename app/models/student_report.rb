require "set"

class StudentReport < ApplicationRecord
  # Reports stored as progress_data (JSONB).
  # As LLMs may not follow the desired schema for reports, don't depend on any particular JSON format. Design around parsing/displaying any contents of the progress_data.

  belongs_to :reportable, polymorphic: true # allows any model to have a StudentReport through reportable (eg. lesson report, enrollment report, misc)
  belongs_to :student, class_name: "User", inverse_of: :student_reports, optional: false
  belongs_to :teacher, class_name: "User", inverse_of: :authored_reports, optional: true # if teacher is deleted, report can remain

  has_many :memories, dependent: :nullify # If memory was based on the report

  enum :author_type, { ai_generated: "ai_generated", teacher_written: "teacher_written" }, prefix: true
  enum :status, { in_progress: "in_progress", completed: "completed" }, prefix: true # Not currently needed

  validates :author_type, presence: true
  validates :status, presence: true

  after_create_commit :trigger_course_report_check, if: -> { reportable_type == "LessonProgress" }
  after_create_commit :trigger_memory_backfill, if: -> { reportable_type == "LessonProgress" }
  after_create_commit :trigger_observation_generation, if: -> { reportable_type == "LessonProgress" }
  after_create_commit :trigger_notification, if: -> { reportable_type == "LessonProgress" }

  scope :lesson_reports, -> { where(reportable_type: "LessonProgress") }
  scope :course_reports, -> { where(reportable_type: "Enrollment") }
  scope :profile_reports, -> { where(reportable_type: "User") }
  scope :orphaned, -> { where(reportable_id: nil) }

  def to_markdown
      report = progress_data
      return "" unless report.present?
      return report.to_s unless report.is_a?(Hash)
    begin
      md = +""
      ordered_report_pairs.each do |key, value|
        # Convert the key (symbol or string) to a humanized heading.
        md << "**#{key.to_s.humanize}**\n"
        case value
        when Array
          if value.empty?
            md << "None.\n\n"
          else
            value.each do |item|
              md << "- #{item}\n"
            end
            md << "\n"
          end
        else
          md << "#{value}\n\n"
        end
      end
      md
    rescue StandardError => e
      Rails.logger.error "Error generating markdown for student report #{id}: #{e.message}"
      report.to_s
    end
  end

  private

  # NOTE: PostgreSQL jsonb does not preserve object key insertion order (keys get canonicalized),
  # so we must not rely on Hash iteration order for display.
  def ordered_report_pairs
    return [] unless progress_data.is_a?(Hash)

    order =
      case reportable_type
      when "User"
        GenerateStudentProfileJob::PROFILE_KEY_ORDER
      end

    return progress_data.map { |key, value| [ key, value ] } if order.blank?

    seen = Set.new
    pairs = []

    order.each do |key|
      value = progress_data[key] || progress_data[key.to_sym]
      next if value.nil?
      seen.add(key.to_s)
      pairs << [ key, value ]
    end

    progress_data.each do |key, value|
      next if seen.include?(key.to_s)
      pairs << [ key, value ]
    end

    pairs
  end

  def trigger_course_report_check
    Rails.logger.debug "Checking if need course report for student #{student.id} in course #{reportable.lesson.course.id}"
    enrollment = reportable.lesson.course.enrollments.find_by(student: student)
    enrollment.course_report_check
  end

  # After LLM saves a lesson progress report, start job to semantically merge the memories.
  def trigger_memory_backfill
    return unless progress_data&.dig("memories").present?
    BackfillMemoriesFromLessonReportJob.set(wait: 5.seconds).perform_later(self)
  end

  # Trigger observation generation regardless of specific content, as the LLM will derive them.
  def trigger_observation_generation
    GenerateObservationsJob.set(wait: 5.seconds).perform_later(self)
  end

  def trigger_notification
    Rails.logger.debug "Triggering notification for student report #{id}"

    # Notify the student's teacher, if they have one
    recipient_id = student.teacher&.id
    return unless recipient_id

    lesson = reportable&.lesson
    link = Rails.application.routes.url_helpers.admin_student_path(
      student,
      active_tab: "journal_timeline",
      anchor: "student_report_#{id}"
    )

    Rails.event.notify(Events::LessonComplete.new(
      recipient_ids: recipient_id,
      link: link,
      student_name: student.name,
      lesson_title: lesson&.title || "Unknown Lesson",
      report_id: id
    ))
  end
end
