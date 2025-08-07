class StudentReport < ApplicationRecord
  # Reports stored as progress_data (JSONB).
  # As LLMs may not follow the desired schema for reports, don't depend on any particular JSON format.

  belongs_to :reportable, polymorphic: true # allows any model to have a StudentReport through reportable (eg. lesson report, enrollment report, misc)
  belongs_to :student, class_name: "User", inverse_of: :student_reports, optional: false
  belongs_to :teacher, class_name: "User", inverse_of: :authored_reports, optional: true # if teacher is deleted, report can remain

  enum :author_type, { ai_generated: "ai_generated", teacher_written: "teacher_written" }, prefix: true
  enum :status, { in_progress: "in_progress", completed: "completed" }, prefix: true

  # Automatically check if student course report needs to be generated
  after_create :trigger_course_report_check

  scope :lesson_reports, -> { where(reportable_type: "LessonProgress") }
  scope :course_reports, -> { where(reportable_type: "Enrollment") }
  scope :orphaned, -> { where(reportable_id: nil) }

  def to_markdown
      report = progress_data
      return report.to_s unless report.is_a?(Hash)
    begin
      md = +""
      report.each do |key, value|
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

  def trigger_course_report_check
    if reportable_type == "LessonProgress"
      Rails.logger.debug "Checking if need course report for student #{student.id} in course #{reportable.lesson.course.id}"
      enrollment = reportable.lesson.course.enrollments.find_by(student: student)
      enrollment.course_report_check
    end
  end
end
