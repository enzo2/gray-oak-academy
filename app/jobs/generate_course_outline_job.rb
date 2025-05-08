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

  def perform(course, current_user)
    customized_prompt = Prompt.get_prompt(category: "generate_course_outline", user: current_user)
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt } ]

    begin
      # Make the LLM request
      client = OpenaiApiService.new(current_user: current_user)
      parsed_outline = client.complete(
        messages,
        response_format: {
          type: "json_schema",
          json_schema: OUTLINE_SCHEMA
        },
        schema: OUTLINE_SCHEMA["schema"],  # Also pass the schema to the wrapper service for validation of the response
        prefill: "{\"outline\": ["
      )

      # Update the course with the generated outline.
      extracted_outline = parsed_outline["outline"].map do |item|
        { item["topic"] => item["description"] }
      end
      course.update!(outline: extracted_outline)

      # Broadcast the updated course outline
      broadcast_success(course, current_user)

    rescue StandardError => e
      Rails.logger.error "Job Error: #{e.message}"
      broadcast_error(
        current_user,
        course,
        "Failed to generate course outline: #{e.message}"
      )
    end
  end

  private

  def broadcast_success(course, current_user)
    Rails.logger.info "Broadcasting success for course: #{course.id}"
    # Broadcast the updated course row via Turbo Streams
    renderer = ApplicationController.renderer_with_signed_in_user(current_user)
    html = renderer.render(
      template: "admin/courses/edit",
      layout: false,
      locals: { course: course }
    )
    Turbo::StreamsChannel.broadcast_update_to(
      "teacher_#{current_user.id}-dashboard",
     target: course,
     html: html
     )
    Turbo::StreamsChannel.broadcast_update_to(
      "teacher_#{current_user.id}-dashboard",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { success: "Course outline generated successfully!" } }
      )
  end

  def broadcast_error(current_user, course, message)
    # Broadcast an error message via Turbo Streams
    Turbo::StreamsChannel.broadcast_update_to(
      "teacher_#{current_user.id}-dashboard",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
    # Re-render the course row to reset the button state
    Turbo::StreamsChannel.broadcast_replace_to(
      "teacher_#{current_user.id}-dashboard",
      target: course,
      partial: "admin/courses/course",
      locals: { course: course }
    )
  end
end
