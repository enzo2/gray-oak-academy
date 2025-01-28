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

  TASK_PROMPT = Prompt.category_generate_course_outline.first.prompt

  def perform(course, current_user)
    customized_prompt = TASK_PROMPT
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)

    # Prepare messages for the LLM
    messages = [
      { role: "user", content: customized_prompt }
      # try prefilling the assistant message
    ]

    begin
      # Make the LLM request
      client = OpenRouterService.new(
        models: [ current_user.setting.llm_model_name ],
        access_token: current_user.setting.llm_api_access_token
      )
      parsed_content = client.complete(
        messages,
        extras: {
          response_format: {
            type: "json_object"
          }
        },
        schema: OUTLINE_SCHEMA
      )

      # Update the course with the generated outline. (Stored as array in JSONB column.)
      course.update!(outline: parsed_content)

      # Broadcast the updated course outline
      broadcast_success(course)

    rescue StandardError => e
      Rails.logger.error "Job Error: #{e.message}"
      broadcast_error(course, "Failed to generate course outline: #{e.message}")
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
      locals: { flash: { error: message } }
    )
  end
end
