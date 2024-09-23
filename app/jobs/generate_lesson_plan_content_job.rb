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

  def perform(lesson_plan)
    lesson = lesson_plan.lesson
    course = lesson.course
    customized_prompt = TASK_PROMPT
      .gsub("{title}", lesson.title)
      .gsub("{goals}", lesson.goals)
      .gsub("{approx_duration_min}", lesson.approx_duration_min.to_s)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_title}", course.title)
      .gsub("{other_lessons}", lesson.course.lessons.where.not(id: lesson.id).map(&:title).join(", "))

    # Initialize LLM client
    require "faraday/retry"
    retry_options = {
      max: 2,
      interval: 0.05,
      interval_randomness: 0.5,
      backoff_factor: 2
    }
    client = OpenRouter::Client.new(access_token: ENV["OPENROUTER_ACCESS_TOKEN"]) do |config|
      config.faraday do |f|
        f.request :retry, retry_options
        f.response :logger, ::Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
          logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
        end
      end
    end

    # Prepare messages for the LLM
    messages = [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: customized_prompt }
    ]

    begin
      # Make the LLM request
      response = client.complete(
        messages,
        model: [
          ENV["OPENROUTER_MODEL_NAME"]
        ],
        extras: {
          response_format: {
            type: "json_object"
          }
        }
      )

      # Extract the response
      content = response.dig("choices", 0, "message", "content")
      unless content.present?
        raise "Empty response from LLM."
      end

      # Extract valid JSON from the response
      json_content = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
      unless json_content
        raise "No valid JSON found in the LLM response."
      end

      # Parse the JSON
      begin
        parsed_content = JSON.parse(json_content)
      rescue JSON::ParserError => e
        raise "Failed to parse JSON from LLM response: #{e.message}"
      end

      # Validate the parsed content against the schema
      schemer = JSONSchemer.schema(CONTENT_SCHEMA)
      unless schemer.valid?(parsed_content)
        errors = schemer.validate(parsed_content).to_a
        raise "Invalid content structure: #{errors.map { |e| e['error'] }.join(', ')}"
      end

      # Update the lesson plan with the generated content (Stored as array in JSONB column.)
      lesson_plan.update!(content: parsed_content)

      # Broadcast the updated lesson plan content
      broadcast_success(lesson_plan, lesson, course)

    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parsing Error: #{e.message}"
      broadcast_error(lesson_plan, "Invalid JSON format from LLM response.")
    rescue StandardError => e
      Rails.logger.error "LLM Error: #{e.message}"
      broadcast_error(lesson_plan, "Failed to generate lesson plan content.")
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
