class GenerateCourseReportJob < ApplicationJob
  queue_as :default

  REPORT_SCHEMA = {
    strict: true,
    name: "Course_Report",
    description: "A summary of the student's performance in the course.",
    schema: LlmSchemas::CourseReportSchema.to_json_schema.deep_stringify_keys
  }

  def perform(enrollment)
    course = enrollment.course
    student = enrollment.student
    teacher = course.teacher
    lessons_history = enrollment.lesson_history_for_prompt
    task_prompt = Prompt.get_prompt(category: "generate_student_course_report", user: teacher)

    customized_prompt = task_prompt
      .gsub("{course_title}", course.title)
      .gsub("{course_summary}", course.summary)
      .gsub("{lessons}", lessons_history)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt } ]

    begin
      # Make the LLM request
      client = OpenaiApiService.new(
        current_user: teacher,
        reasoning_model: true
      )
      parsed_content = client.complete(
        messages,
        response_format: {
          type: "json_schema",
          json_schema: REPORT_SCHEMA.slice(:name, :schema, :strict)
        },
        schema: REPORT_SCHEMA[:schema],
        prefill: "{"
      )

      # Create the student report
      report = StudentReport.create!(
        student: student,
        teacher: teacher,
        reportable: enrollment,
        progress_data: parsed_content,
        author_type: :ai_generated,
        status: :completed
      )

      Rails.logger.info "Course report generated for enrollment: #{enrollment.id}"

      link = Rails.application.routes.url_helpers.admin_student_path(
        student,
        active_tab: "journal_timeline",
        anchor: "student_report_#{report.id}"
      )

      Rails.event.notify(Events::EnrollmentReportGenerated.new(
        recipient_ids: teacher.id,
        link: link,
        student_name: student.name,
        course_title: course.title,
        report_id: report.id
      ))

    rescue StandardError => e
      Rails.logger.error "Error generating course report for enrollment #{enrollment.id}: #{e.message}"
      # Optionally, broadcast an error message
    end
  end
end
