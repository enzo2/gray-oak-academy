class GenerateCourseLessonsJob < ApplicationJob
  queue_as :default

  LESSONS_SCHEMA = {
    "strict": true,
    "name": "Course_Lessons",
    "description": "An array of lesson objects for the course",
    "schema": {
      "type": "object",
      "properties": {
        "lessons": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "title": { "type": "string" },
              "goals": { "type": "string" },
              "duration": { "type": "integer" }
            },
            "required": [ "title", "goals", "duration" ],
            "additionalProperties": false
          }
        }
      },
      "required": [ "lessons" ],
      "additionalProperties": false
    }
  }

  def perform(course, current_user)
    customized_prompt = Prompt.get_prompt(category: "generate_lessons", user: current_user)
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_outline}", course.outline.to_json)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt } ]

    begin
      # Make the LLM request
      client = OpenaiApiService.new(
        current_user: current_user
      )
      parsed_content = client.complete(
        messages,
        response_format: {
          type: "json_schema",
          json_schema: LESSONS_SCHEMA
        },
        schema: LESSONS_SCHEMA,
        prefill: "{\"lessons\": ["
      )

      # Create lessons for the course
      parsed_content["lessons"].each do |lesson|
        course.lessons.create!(
          title: lesson["title"],
          goals: lesson["goals"],
          approx_duration_min: lesson["duration"]
        )
      end

      # Broadcast the updated course with lessons
      broadcast_success(course)

    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      broadcast_error(course, "Failed to generate course lessons: #{e.message}")
    end
  end

  private

  def broadcast_success(course)
    Rails.logger.info "Broadcasting success for course: #{course.id}"
    Turbo::StreamsChannel.broadcast_update_to(
      "teacher-dashboard",
      target: "lessons-table-body",
      partial: "admin/lessons/lessons_table",
      locals: { course: course }
    )
    Turbo::StreamsChannel.broadcast_remove_to(
      "teacher-dashboard",
      target: "generate-lessons"
    )
  end

  def broadcast_error(course, message)
    # Broadcast an error message via Turbo Streams
    Turbo::StreamsChannel.broadcast_update_to("teacher-dashboard",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
  end
end
