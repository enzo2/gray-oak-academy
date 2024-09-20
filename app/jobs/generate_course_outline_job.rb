class GenerateCourseOutlineJob < ApplicationJob
  queue_as :default

  OUTLINE_SCHEMA = {
    type: "object",
    propertyNames: { type: "string" },
    additionalProperties: { type: "string" },
    minProperties: 1
  }

  def perform(course)
    # Fetch the prompt template
    prompt_template = Prompt.category_generate_course_outline.first
    unless prompt_template.present?
      broadcast_error(course, "Prompt not found.")
      return
    end

    # Customize the prompt
    customized_prompt = customize_prompt(prompt_template.prompt, course)

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
      { role: "system", content: "You are an expert curriculum designer for all forms of education from Kindergarden through PhD level." },
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

      # Extract and parse the outline
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

      # Transform the parsed outline into an array to maintain order in the DB
      formatted_outline = format_outline(parsed_outline)

      # Update the course with the generated outline
      course.update!(outline: formatted_outline)

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

  def customize_prompt(template, course)
    template
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)
  end

  def format_outline(parsed_outline)
    parsed_outline.map { |topic, details| { topic => details } }
  end

  def broadcast_success(course)
    Rails.logger.info "Broadcasting success for course: #{course.id}"
    # Broadcast the updated course row via Turbo Streams
    Turbo::StreamsChannel.broadcast_replace_to("teacher-dashboard", target: course, partial: "admin/courses/course", locals: { course: course })
  end

  def broadcast_error(course, message)
    # Broadcast an error message via Turbo Streams
    Turbo::StreamsChannel.broadcast_update_to("teacher-dashboard", target: "flash_bar", partial: "shared/flash", locals: { type: "error", message: message })
  end
end
