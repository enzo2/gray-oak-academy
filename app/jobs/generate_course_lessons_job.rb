class GenerateCourseLessonsJob < ApplicationJob
  queue_as :default

  LESSONS_SCHEMA = {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "title": {
          "type": "string"
        },
        "goals": {
          "type": "string"
        },
        "duration": {
          "type": "integer"
        }
      },
      "required": [ "title", "goals", "duration" ]
    },
    "minItems": 1,
    "description": "An array of lesson objects for the course"
  }

  TASK_PROMPT = Prompt.category_generate_lessons.first.prompt

  def perform(course, current_user)
    customized_prompt = TASK_PROMPT
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_outline}", course.outline.to_json)

    # Prepare messages for the LLM
    messages = [
      { role: "user", content: customized_prompt }# ,
      # { role: "assistant", content: "[" } # prefill the response to begin valid JSON
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
            type: "json_object"
          }
        },
        schema: LESSONS_SCHEMA
      )

      # Create lessons for the course
      parsed_content.each do |lesson|
        course.lessons.create!(
          title: lesson["title"],
          goals: lesson["goals"],
          approx_duration_min: lesson["duration"]
        )
      end

      # Broadcast the updated course with lessons
      broadcast_success(course)

    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
      broadcast_error(course, "Failed to generate course lessons: #{e.message}")
    end
  end

  private

  def broadcast_success(course)
    Rails.logger.info "Broadcasting success for course: #{course.id}"
    Turbo::StreamsChannel.broadcast_update_to(
      "teacher-dashboard",
      target: "lessons-table-body",
      partial: "admin/lessons/lessons_table",
      locals: { course: course }
    )
    Turbo::StreamsChannel.broadcast_remove_to(
      "teacher-dashboard",
      target: "generate-lessons"
    )
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
