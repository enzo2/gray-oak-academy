class GenerateLessonPlanContentJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(lesson_plan, *, **) { "lesson-plan-content-#{lesson_plan.id}" }, duration: 10.minutes

  CONTENT_SCHEMA = {
    strict: true,
    name: "Lesson_Plan",
    description: "A detailed lesson plan content and strategy outline.",
    schema: LlmSchemas::LessonPlanSchema.to_json_schema.deep_stringify_keys
  }

  def perform(lesson_plan, current_user, track_stage: true, raise_on_error: false)
    lesson = lesson_plan.lesson
    course = lesson.course
    set_generation_state(lesson_plan, "generating_content", nil) if track_stage

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
      client = LlmServiceRouting.build_completion_client(current_user: current_user, reasoning_model: true, store: false)

      parsed_content = LlmServiceRouting.complete_structured_output(
        client: client,
        messages: messages,
        response_format: {
          type: "json_schema",
          json_schema: CONTENT_SCHEMA.slice(:name, :schema, :strict)
        },
        schema: CONTENT_SCHEMA[:schema],
        prefill: "{\"lesson_plan\": ["
      )

      # Update the lesson plan with the generated content (Stored as array in JSONB column.)
      unless parsed_content["lesson_plan"].is_a?(Array)
        raise "Invalid response from LLM: 'lesson_plan' must be an array"
      end

      extracted_lesson_plan = parsed_content["lesson_plan"].map do |item|
        { item["type"] => item["details"] }
      end

      resources_array = parsed_content["suggested_resources"] || []
      extracted_suggested_resources = resources_array.map do |item|
        { item["type"] => item["description"] }
      end

      lesson_plan.update!(
        content: extracted_lesson_plan,
        suggested_resources: extracted_suggested_resources
      )
      set_generation_state(lesson_plan, "completed", nil) if track_stage

      # Broadcast the updated lesson plan content
      broadcast_success(current_user, lesson_plan, lesson)
      true

    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      set_generation_state(lesson_plan, "failed", "Failed to generate lesson plan content: #{e.message}") if track_stage
      broadcast_error(current_user, lesson_plan, "Failed to generate lesson plan content: #{e.message}")
      raise if raise_on_error
      false
    end
  end

  private

  def set_generation_state(lesson_plan, stage, error)
    lesson_plan.update!(generation_stage: stage, generation_error: error)
  end

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
    # Restore the button by replacing it with the original partial
    Turbo::StreamsChannel.broadcast_replace_to(
      channel,
      target: "lesson-plan-generation-controls",
      partial: "admin/lesson_plans/generate_lesson_plan_button",
      locals: { lesson: lesson_plan.lesson, lesson_plan: lesson_plan }
    )
  end
end
