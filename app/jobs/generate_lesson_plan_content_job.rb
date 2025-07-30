class GenerateLessonPlanContentJob < ApplicationJob
  queue_as :default

  CONTENT_SCHEMA = {
    "strict": true,
    "name": "Lesson_Plan",
    "description": "A detailed lesson plan content and strategy outline.",
    "schema": {
      "type": "object",
      "properties": {
        "lesson_plan": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "type": { "type": "string" },
              "details": { "type": "string" }
            },
            "required": [ "type", "details" ],
            "additionalProperties": false
          }
        },
        "suggested_resources": {
          "type": "array",
          "description": "A list of suggested resources for the lesson which may need to be located, obtained or validated before use.",
          "items": {
            "type": "object",
            "properties": {
              "type": { "type": "string" },
              "description": { "type": "string" }
            },
            "required": [ "type", "description" ],
            "additionalProperties": false
          }
        }
      },
      "required": [ "lesson_plan" ],
      "additionalProperties": false
    }
  }

  def perform(lesson_plan, current_user)
    lesson = lesson_plan.lesson
    course = lesson.course
    customized_prompt = Prompt.get_prompt(category: "generate_lesson_plan", user: current_user)
      .gsub("{title}", "#{lesson.position}. #{lesson.title}")
      .gsub("{goals}", lesson.goals)
      .gsub("{approx_duration_min}", lesson.approx_duration_min.to_s)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_title}", course.title)
      .gsub("{linked_resources}", lesson.lesson_plan.resources.format_collection)
      .gsub("{other_lessons}", lesson.course.lessons.where.not(id: lesson.id).map { |l| "#{l.position}. #{l.title}" }.join(", "))

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt } ]

    begin
      # Make the LLM request
      client = OpenaiApiService.new(current_user: current_user, reasoning_model: true)

      parsed_content = client.complete(
        messages,
        response_format: {
          type: "json_schema",
          json_schema: CONTENT_SCHEMA
        },
        schema: CONTENT_SCHEMA,
        prefill: "{\"lesson_plan\": ["
      )

      # Update the lesson plan with the generated content (Stored as array in JSONB column.)
      extracted_lesson_plan = parsed_content["lesson_plan"].map do |item|
        { item["type"] => item["details"] }
      end
      extracted_suggested_resources = parsed_content["suggested_resources"].map do |item|
        { item["type"] => item["description"] }
      end
      lesson_plan.update!(
        content: extracted_lesson_plan,
        suggested_resources: extracted_suggested_resources || []
      )

      # Broadcast the updated lesson plan content
      broadcast_success(current_user, lesson_plan, lesson)

    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      broadcast_error(current_user, lesson_plan, "Failed to generate lesson plan content: #{e.message}")
    end
  end

  private

  def broadcast_success(current_user, lesson_plan, lesson)
    Rails.logger.info "Broadcasting success for lesson plan: #{lesson_plan.id}"
    # Broadcast the updated lesson plan via Turbo Streams
    channel = "teacher_#{current_user.id}-dashboard"
    Turbo::StreamsChannel.broadcast_refresh_to(channel)
  end

  def broadcast_error(current_user, lesson_plan, message)
    channel = "teacher_#{current_user.id}-dashboard"
    renderer = ApplicationController.renderer_with_signed_in_user(current_user)
    html = renderer.render(
      partial: "admin/lesson_plans/form",
      locals: { lesson: lesson_plan.lesson, lesson_plan: lesson_plan }
    )
    # Broadcast an error message via Turbo Streams
    Turbo::StreamsChannel.broadcast_append_to(
      channel,
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
    # Restore the button by replacing the form
    Turbo::StreamsChannel.broadcast_replace_to(
      channel, target: "lesson-plan-form", html: html)
  end
end
