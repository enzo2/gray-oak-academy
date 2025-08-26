class GenerateCourseLessonsJob < ApplicationJob
  queue_as :default

  LESSONS_SCHEMA = {
    "strict": true,
    "name": "Course_Lessons",
    "description": "An array of lesson objects for the course",
    "schema": {
      "type": "object",
      "properties": {
        "lessons": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "title": { "type": "string" },
              "goals": { "type": "string" },
              "duration": { "type": "integer" }
            },
            "required": [ "title", "goals", "duration" ],
            "additionalProperties": false
          }
        }
      },
      "required": [ "lessons" ],
      "additionalProperties": false
    }
  }

  def perform(course, current_user)
    # Accomodate existing lessons
    existing_titles = course.lessons.pluck(:title)
    existing_list = "None"
    if existing_titles.any?
      existing_list = "\n" + existing_titles.map.with_index(1) { |t, i| "#{i}. #{t}" }.join("\n")
    end
    # Ensure there is a course outline
    raise "Course outline is blank. Outline needed to generate lessons." if course.outline.blank?

    customized_prompt = Prompt.get_prompt(category: "generate_lessons", user: current_user)
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_outline}", course.outline.to_json)
      .gsub("{existing_lessons}", existing_list)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt } ]

    begin
      # Make the LLM request
      client = OpenaiApiService.new(
        current_user: current_user,
        reasoning_model: true
      )
      parsed_content = client.complete(
        messages,
        response_format: {
          type: "json_schema",
          json_schema: LESSONS_SCHEMA[:schema]
        },
        schema: LESSONS_SCHEMA[:schema],
        prefill: "{\"lessons\": ["
      )

      # Create lessons for the course, skipping duplicates and validating the response shape.
      unless parsed_content["lessons"].is_a?(Array)
        raise "Invalid response from LLM: 'lessons' must be an array"
      end

      parsed_content["lessons"].each do |lesson|
        course.lessons.create!(
          title: lesson["title"],
          goals: lesson["goals"],
          approx_duration_min: lesson["duration"]
        )
      end

      # Broadcast the updated course with lessons
      broadcast_success(current_user, course)

    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      broadcast_error(
        current_user,
        course,
        "Failed to generate course lessons: #{e.message}"
      )
    end
  end

  private

  def broadcast_success(current_user, course)
    Rails.logger.info "Broadcasting success for course: #{course.id}"
    channel = "teacher_#{current_user.id}-dashboard"
    renderer = ApplicationController.renderer_with_signed_in_user(current_user)
    html = renderer.render(
      partial: "admin/lessons/lessons_table",
      locals: { course: course }
    )
    Turbo::StreamsChannel.broadcast_update_to(
      channel,
      target: "lessons-table-body",
      html: html)
    Turbo::StreamsChannel.broadcast_remove_to(
      channel, target: "generate-lessons")
  end

  def broadcast_error(current_user, course, message)
    # Broadcast an error message via Turbo Streams
    Turbo::StreamsChannel.broadcast_update_to(
      "teacher_#{current_user.id}-dashboard",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
    Turbo::StreamsChannel.broadcast_update_to(
      "teacher_#{current_user.id}-dashboard",
      target: "generate-lessons",
      partial: "admin/lessons/generate_lessons_button",
      locals: { course: course }
    )
  end
end
