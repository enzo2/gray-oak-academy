class GenerateCourseReportJob < ApplicationJob
  queue_as :default

  REPORT_SCHEMA = {
    "strict": true,
    "name": "Course_Report",
    "description": "A summary of the student's performance in the course.",
    "schema": {
      "type": "object",
      "properties": {
        "summary": {
          "type": "string",
          "description": "A detailed overview of the student's performance and understanding during the course."
        },
        "strengths": {
          "type": "array",
          "items": { "type": "string" },
          "description": "List areas where the student demonstrated adequate-to-strong understanding, which will require minimal to no review in subsequent courses. May include knowledge, skills, abilities, or other learning targets."
        },
        "areas_for_review": {
          "type": "array",
          "items": { "type": "string" },
          "description": "List aspects (if any) of the course material/plan where the student should receive additional clarification, review or practice in subsequent courses or remedial sessions. May include knowledge, skills, abilities, or other learning targets."
        },
        "teaching_methods": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Note any aspects of teaching methodology that were particularly effective or ineffective for the student."
        },
        "other_observations": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Optional: Note any other observations or notable examples concerning the student's progress and development, such as engagement, attitude, cognition, or other relevant factors."
        }
      }
    }
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
          json_schema: REPORT_SCHEMA[:schema]
        },
        schema: REPORT_SCHEMA[:schema],
        prefill: "{"
      )

      # Create the student report
      StudentReport.create!(
        student: student,
        teacher: teacher,
        reportable: enrollment,
        progress_data: parsed_content,
        author_type: :ai_generated,
        status: :completed
      )

      Rails.logger.info "Course report generated for enrollment: #{enrollment.id}"

    rescue StandardError => e
      Rails.logger.error "Error generating course report for enrollment #{enrollment.id}: #{e.message}"
      # Optionally, broadcast an error message
    end
  end
end
