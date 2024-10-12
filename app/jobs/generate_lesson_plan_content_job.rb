class GenerateLessonPlanContentJob < ApplicationJob
  queue_as :default

  CONTENT_SCHEMA = {
    "type": "array",
    "items": {
      "type": "object",
      "propertyNames": { "type": "string" },
      "additionalProperties": false,
      "minProperties": 1,
      "maxProperties": 1,
      "patternProperties": {
        "^.*$": { "type": "string" }
      }
    },
    "minItems": 1
  }

  SYSTEM_PROMPT = Prompt.category_base_system_prompt.first.prompt + Prompt.category_teaching_principles.first.prompt
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
    messages = [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: customized_prompt }
    ]

    begin
      # Make the LLM request
      client = OpenRouterService.new(
        models: [ current_user.setting.openrouter_model ],
        access_token: current_user.setting.openrouter_access_token
      )
      parsed_content = client.complete(
        messages,
        extras: {
          response_format: {
            type: "json_object"
          }
        },
        schema: CONTENT_SCHEMA
      )

      # Update the lesson plan with the generated content (Stored as array in JSONB column.)
      lesson_plan.update!(content: parsed_content)

      # Broadcast the updated lesson plan content
      broadcast_success(lesson_plan, lesson, course)

    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      broadcast_error(lesson_plan, "Failed to generate lesson plan content: #{e.message}")
    end
  end

  private

  def broadcast_success(lesson_plan, lesson, course)
    Rails.logger.info "Broadcasting success for lesson plan: #{lesson_plan.id}"
    # Broadcast the updated lesson plan row via Turbo Streams
    # Turbo::StreamsChannel.broadcast_replace_to("teacher-dashboard", target: "lesson-plan-form", partial: "admin/lesson_plans/form", locals: { course: course, lesson: lesson, lesson_plan: lesson_plan })
    Turbo::StreamsChannel.broadcast_replace_to("teacher-dashboard",
      target: "lesson-plan-form",
      partial: "admin/lesson_plans/form",
      locals: { course: course, lesson: lesson, lesson_plan: lesson_plan })

    # Hide the loading indicator
    Turbo::StreamsChannel.broadcast_remove_to("teacher-dashboard", target: "lesson-plan-loading")
  end

  def broadcast_error(lesson_plan, message)
    # Broadcast an error message via Turbo Streams
    Turbo::StreamsChannel.broadcast_update_to("teacher-dashboard",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { type: "error", message: message } }
    )
    # Hide the loading indicator
    Turbo::StreamsChannel.broadcast_remove_to("teacher-dashboard", target: "lesson-plan-loading")
  end
end
