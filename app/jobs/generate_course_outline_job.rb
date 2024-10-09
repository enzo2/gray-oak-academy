class GenerateCourseOutlineJob < ApplicationJob
  queue_as :default

  OUTLINE_SCHEMA = {
    "type": "array",
    "items": {
      "type": "object",
      "propertyNames": { "type": "string" },
      "patternProperties": {
        "^.*$": { "type": "string" }
      },
      "additionalProperties": false,
      "minProperties": 1,
      "maxProperties": 1
    },
    "minItems": 1
  }

  SYSTEM_PROMPT = Prompt.category_base_system_prompt.first.prompt + Prompt.category_teaching_principles.first.prompt
  TASK_PROMPT = Prompt.category_generate_course_outline.first.prompt

  def perform(course, current_user)
    customized_prompt = TASK_PROMPT
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)

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

      # Validate the parsed outline against the schema
      schemer = JSONSchemer.schema(OUTLINE_SCHEMA)
      unless schemer.valid?(parsed_content)
        errors = schemer.validate(parsed_content).to_a
        raise "Invalid outline structure: #{errors.map { |e| e['error'] }.join(', ')}"
      end

      # Update the course with the generated outline. (Stored as array in JSONB column.)
      course.update!(outline: parsed_content)

      # Broadcast the updated course outline
      broadcast_success(course)

    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parsing Error: #{e.message}"
      broadcast_error(course, "Invalid JSON format from LLM response.")
    rescue StandardError => e
      Rails.logger.error "LLM Error: #{e.message}"
      broadcast_error(course, "Failed to generate course outline.")
    end
  end

  private

  def broadcast_success(course)
    Rails.logger.info "Broadcasting success for course: #{course.id}"
    # Broadcast the updated course row via Turbo Streams
    Turbo::StreamsChannel.broadcast_replace_to("teacher-dashboard", target: course, partial: "admin/courses/course", locals: { course: course })
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
