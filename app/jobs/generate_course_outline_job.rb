class GenerateCourseOutlineJob < ApplicationJob
  queue_as :default

  OUTLINE_SCHEMA = {
    "strict": true,
    "name": "Course_Outline",
    "description": "A thorough proposal of course content organized into topics, each with a brief description.",
    "schema": {
      "type": "object",
      "properties": {
        "outline": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "topic": { "type": "string" },
              "description": { "type": "string" }
            },
            "required": [ "topic", "description" ],
            "additionalProperties": false
          }
        }
      },
      "required": [ "outline" ],
      "additionalProperties": false
    }
  }

  TASK_PROMPT = Prompt.category_generate_course_outline.first.prompt

  def perform(course, current_user)
    customized_prompt = TASK_PROMPT
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt },
                 { role: "assistant", content: "{\"outline\": [{" } # Prefill the response to help it respond with valid JSON
   ]

    begin
      # Make the LLM request
      client = OpenaiApiService.new(
        model: current_user.setting.llm_model_name,
        access_token: current_user.setting.llm_api_access_token
      )
      parsed_content = client.complete(
        messages,
        extras: {
          response_format: {
            # type: "json_object"  # Non-strict option, if need to support APIs that lack structured output support
            type: "json_schema",
            json_schema: OUTLINE_SCHEMA
          }
        },
        schema: OUTLINE_SCHEMA["schema"]  # Also pass the schema to the wrapper service for validation of the response
      )

      # Update the course with the generated outline.
      extracted_outline = parsed_content["outline"].map do |item|
        { item["topic"] => item["description"] }
      end
      course.update!(outline: extracted_outline)

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
    Turbo::StreamsChannel.broadcast_replace_to("teacher-dashboard",
      target: course,
      partial: "admin/courses/course",
      locals: { course: course })
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
