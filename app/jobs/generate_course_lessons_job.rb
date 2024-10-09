class GenerateCourseLessonsJob < ApplicationJob
  queue_as :default

  LESSONS_SCHEMA = {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "title": {
          "type": "string"
        },
        "goals": {
          "type": "string"
        },
        "duration": {
          "type": "integer"
        }
      },
      "required": [ "title", "goals", "duration" ]
    },
    "minItems": 1,
    "description": "An array of lesson objects for the course"
  }

  SYSTEM_PROMPT = Prompt.category_base_system_prompt.first.prompt + Prompt.category_teaching_principles.first.prompt
  TASK_PROMPT = Prompt.category_generate_lessons.first.prompt

  def perform(course, current_user)
    customized_prompt = TASK_PROMPT
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_outline}", course.outline.to_json)

    # Prepare messages for the LLM
    messages = [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: customized_prompt }
    ]

    begin
      # Make the LLM request
      client = OpenRouterService.new(
        model: current_user.setting.openrouter_model,
        access_token: current_user.setting.openrouter_access_token
      )
      parsed_content = client.complete(
        messages,
        extras: {
          response_format: {
            type: "json_object"
          }
        }
      )

      # Validate the parsed lessons against the schema
      schemer = JSONSchemer.schema(LESSONS_SCHEMA)
      unless schemer.valid?(parsed_content)
        errors = schemer.validate(parsed_content).to_a
        # Retry ?
        raise "Invalid lessons structure: #{errors.map { |e| e['error'] }.join(', ')}"
      end

      # Create lessons for the course
      parsed_content.each do |lesson|
        course.lessons.create!(
          title: lesson["title"],
          goals: lesson["goals"],
          approx_duration_min: lesson["duration"]
        )
      end

      # Broadcast the updated course with lessons
      broadcast_success(course)

    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parsing Error: #{e.message}"
      broadcast_error(course, "Invalid JSON format from LLM response.")
    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      broadcast_error(course, "Failed to generate course lessons.")
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
      locals: { flash: { type: "error", message: message } }
    )
  end
end
