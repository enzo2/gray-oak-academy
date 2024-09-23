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

  def perform(course)
    customized_prompt = TASK_PROMPT
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)

    # require 'faraday'
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
          "anthropic/claude-3.5-sonnet:beta"
        ],
        extras: {
          response_format: {
            type: "json_object"
          }
        }
      )

      # Extract the response
      outline_content = response.dig("choices", 0, "message", "content")
      unless outline_content.present?
        raise "Empty response from LLM."
      end

      # Extract valid JSON from the response
      json_content = outline_content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
      unless json_content
        raise "No valid JSON found in the LLM response."
      end

      # Rails.logger.info "LLM Response: #{json_content}"

      # Parse the JSON
      begin
        parsed_outline = JSON.parse(json_content)
      rescue JSON::ParserError => e
        raise "Failed to parse JSON from LLM response: #{e.message}"
      end

      # Validate the parsed outline against the schema
      schemer = JSONSchemer.schema(OUTLINE_SCHEMA)
      unless schemer.valid?(parsed_outline)
        errors = schemer.validate(parsed_outline).to_a
        raise "Invalid outline structure: #{errors.map { |e| e['error'] }.join(', ')}"
      end

      # Update the course with the generated outline. (Stored as array in JSONB column.)
      course.update!(outline: parsed_outline)

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
