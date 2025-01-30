class GenerateLessonPlanContentJob < ApplicationJob
  queue_as :default

  CONTENT_SCHEMA = {
    "strict": true,
    "name": "Lesson_Plan",
    "description": "A detailed lesson plan content outline.",
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
        }
      },
      "required": [ "lesson_plan" ],
      "additionalProperties": false
    }
  }

  TASK_PROMPT = Prompt.category_generate_lesson_plan.first.prompt

  def perform(lesson_plan, current_user)
    lesson = lesson_plan.lesson
    course = lesson.course
    customized_prompt = TASK_PROMPT
      .gsub("{title}", lesson.title)
      .gsub("{goals}", lesson.goals)
      .gsub("{approx_duration_min}", lesson.approx_duration_min.to_s)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_title}", course.title)
      .gsub("{other_lessons}", lesson.course.lessons.where.not(id: lesson.id).map(&:title).join(", "))

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt } ]

    begin
      # Make the LLM request
      client = OpenaiApiService.new(current_user: current_user)

      parsed_content = client.complete(
        messages,
        extras: {
          response_format: {
            type: "json_schema",
            json_schema: CONTENT_SCHEMA
          }
        },
        schema: CONTENT_SCHEMA,
        prefill: "{\"lesson_plan\": ["
      )

      # Update the lesson plan with the generated content (Stored as array in JSONB column.)
      extracted_content = parsed_content["lesson_plan"].map do |item|
        { item["type"] => item["details"] }
      end
      lesson_plan.update!(content: extracted_content)

      # Broadcast the updated lesson plan content
      broadcast_success(lesson_plan, lesson)

    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      broadcast_error(lesson_plan, "Failed to generate lesson plan content: #{e.message}")
    end
  end

  private

  def broadcast_success(lesson_plan, lesson)
    Rails.logger.info "Broadcasting success for lesson plan: #{lesson_plan.id}"
    # Broadcast the updated lesson plan row via Turbo Streams
    Turbo::StreamsChannel.broadcast_replace_to("teacher-dashboard",
      target: "lesson-plan-form",
      partial: "admin/lesson_plans/form",
      locals: { lesson: lesson, lesson_plan: lesson_plan })

    # Hide the loading indicator
    Turbo::StreamsChannel.broadcast_remove_to("teacher-dashboard", target: "lesson-plan-loading")
  end

  def broadcast_error(lesson_plan, message)
    # Broadcast an error message via Turbo Streams
    Turbo::StreamsChannel.broadcast_update_to("teacher-dashboard",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
    # Hide the loading indicator
    Turbo::StreamsChannel.broadcast_remove_to("teacher-dashboard", target: "lesson-plan-loading")
  end
end
