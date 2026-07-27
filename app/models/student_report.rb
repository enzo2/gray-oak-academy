require "set"

class StudentReport < ApplicationRecord
  EDITABLE_REPORT_TYPES = %w[LessonProgress Enrollment].freeze
  LESSON_REPORT_FIELDS = %w[
    summary strengths areas_for_review teaching_methods other_observations memories
  ].freeze
  COURSE_REPORT_FIELDS = %w[
    summary strengths areas_for_review teaching_methods other_observations
  ].freeze
  LIST_FIELDS = %w[
    strengths areas_for_review teaching_methods other_observations memories
  ].freeze

  # Reports stored as progress_data (JSONB).
  # As LLMs may not follow the desired schema for reports, don't depend on any particular JSON format. Design around parsing/displaying any contents of the progress_data.

  belongs_to :reportable, polymorphic: true # allows any model to have a StudentReport through reportable (eg. lesson report, enrollment report, misc)
  belongs_to :student, class_name: "User", inverse_of: :student_reports, optional: false
  belongs_to :teacher, class_name: "User", inverse_of: :authored_reports, optional: true # if teacher is deleted, report can remain
  belongs_to :edited_by, class_name: "User", optional: true

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

  def teacher_editable?
    reportable_type.in?(EDITABLE_REPORT_TYPES)
  end

  def editable_fields
    data = normalized_progress_data
    ordered_keys = expected_field_keys | data.keys

    ordered_keys.index_with { |key| data.fetch(key) { default_value_for(key) } }
  end

  def editable_field_kind(key)
    value = editable_fields[key.to_s]
    return :json if value.is_a?(Hash) || (value.is_a?(Array) && !value.all?(String))
    return :list if key.to_s.in?(LIST_FIELDS) || value.is_a?(Array)
    return :json unless value.is_a?(String)

    :text
  end

  def editable_field_value(key)
    key = key.to_s
    if defined?(@submitted_editable_fields) && @submitted_editable_fields.key?(key)
      return @submitted_editable_fields[key].to_s
    end

    value = editable_fields[key]

    case editable_field_kind(key)
    when :list
      Array(value).join("\n")
    when :json
      JSON.pretty_generate(value)
    else
      value.to_s
    end
  end

  def apply_teacher_edits(raw_fields, editor:)
    fields = raw_fields.to_h.stringify_keys
    @submitted_editable_fields = fields
    data = normalized_progress_data

    unless editor&.role_teacher?
      errors.add(:edited_by, "must be a teacher")
      return false
    end

    editable_fields.each_key do |key|
      next unless fields.key?(key)

      data[key] = normalize_edited_value(key, fields[key])
    rescue JSON::ParserError
      errors.add(key.to_sym, "must contain valid JSON")
    end

    return false if errors.any?

    self.progress_data = data
    self.edited_by = editor
    self.edited_at = Time.current
    save
  end

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

  def normalized_progress_data
    return progress_data.deep_stringify_keys if progress_data.is_a?(Hash)
    return { "summary" => progress_data.to_s } if progress_data.present?

    {}
  end

  def expected_field_keys
    case reportable_type
    when "LessonProgress"
      LESSON_REPORT_FIELDS
    when "Enrollment"
      COURSE_REPORT_FIELDS
    else
      []
    end
  end

  def default_value_for(key)
    key.in?(LIST_FIELDS) ? [] : ""
  end

  def normalize_edited_value(key, raw_value)
    case editable_field_kind(key)
    when :list
      raw_value.to_s.lines.map(&:strip).reject(&:blank?)
    when :json
      JSON.parse(raw_value.to_s)
    else
      raw_value.to_s.strip
    end
  end

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
