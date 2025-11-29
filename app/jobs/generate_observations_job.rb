class GenerateObservationsJob < ApplicationJob
  queue_as :default

  OBSERVATIONS_SCHEMA = {
    "name": "Key_Observations",
    "description": "A list of key observations derived from the lesson.",
    "strict": true,
    "schema": {
      "type": "object",
      "properties": {
        "observations": {
          "type": "array",
          "items": { "type": "string" },
          "description": "1-3 distinct, high-value observations about the student's learning."
        }
      },
      "required": [ "observations" ],
      "additionalProperties": false
    }
  }

  def perform(student_report)
    return unless student_report.reportable_type == "LessonProgress"

    student = student_report.student
    teacher = student.role_teacher? ? student : student.teacher
    lesson_progress = student_report.reportable

    unless lesson_progress
      Rails.logger.warn "GenerateObservationsJob: Reportable (LessonProgress) not found for report #{student_report.id}. Skipping."
      return
    end

    # Retrieve the prompt
    task_prompt = Prompt.get_prompt(category: "generate_observations", user: teacher)
    # Prepare context: Report content + Recent observations
    # Let's include the time created
    recent_observations = student.observations.approved
                          .order(created_at: :desc).limit(20)
                          .map { |o| "- #{o.content} [Observed: #{o.created_at.strftime("%B %d, %Y")}]" }.join("\n")

    prompt = task_prompt
              .gsub("{lesson_report}", student_report.progress_data.to_json)
              .gsub("{recent_observations}", recent_observations.presence || "None")
              .gsub("{current_date}", Time.current.strftime("%B %d, %Y"))

    messages = [ { role: "user", content: prompt } ]

    begin
      client = OpenaiApiService.new(
        current_user: teacher,
        reasoning_model: true
      )

      response = client.complete(
        messages,
        response_format: {
          type: "json_schema",
          json_schema: OBSERVATIONS_SCHEMA[:schema]
        },
        schema: OBSERVATIONS_SCHEMA[:schema],
        prefill: "{ \"observations\": ["
      )

      new_observations = response["observations"] || []

      # Deduplication -- could add here.

      new_observations.each do |obs_text|
        # Create pending observation
        Observation.create!(
          student: student,
          source: lesson_progress, # Link to the lesson progress
          author: nil, # AI author
          content: obs_text,
          status: :pending
        )
      end

      Rails.logger.info "Generated #{new_observations.count} observations for student #{student.id}"

    rescue StandardError => e
      Rails.logger.error "Error generating observations: #{e.message}"
    end
  end
end
