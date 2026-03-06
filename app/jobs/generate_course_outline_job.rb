class GenerateCourseOutlineJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(course, *) { "generate-course-outline-#{course.id}" }, duration: 10.minutes
  include Rails.application.routes.url_helpers

  OUTLINE_SCHEMA = {
    strict: true,
    name: "Course_Outline",
    description: "A thorough proposal of course content organized into topics, each with a brief description.",
    schema: LlmSchemas::CourseOutlineSchema.to_json_schema.deep_stringify_keys
  }.freeze

  def perform(course, current_user)
    customized_prompt = Prompt.get_prompt(category: "generate_course_outline", user: current_user)
      .gsub("{title}", course.title)
      .gsub("{summary}", course.summary)
      .gsub("{grade_level}", course.grade_level)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt } ]

    begin
      # Make the LLM request
      client = LlmServiceRouting.build_completion_client(current_user: current_user, reasoning_model: true, store: false)
      parsed_outline = LlmServiceRouting.complete_structured_output(
        client: client,
        messages: messages,
        response_format: {
          type: "json_schema",
          json_schema: OUTLINE_SCHEMA.slice(:name, :schema, :strict)
        },
        schema: OUTLINE_SCHEMA[:schema],
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
    channel = "teacher_#{current_user.id}-dashboard"
    renderer = ApplicationController.renderer_with_signed_in_user(current_user)
    html = renderer.render(
      partial: "admin/courses/course", locals: { course: course }, layout: false
    )

    # Broadcast the updated course row so the button is back to normal, in case user navigates back
    Turbo::StreamsChannel.broadcast_replace_to(
      channel, target: course, html: html
    )

    # Broadcast a visit action to navigate to the edit page so user sees the new outline
    Turbo::StreamsChannel.broadcast_action_to(
      channel, action: :visit,
      attributes: { "url": "#{edit_admin_course_path(course)}" }
    )
  end

  def broadcast_error(current_user, course, message)
    Rails.logger.error "Broadcasting error for course: #{course.id}"
    channel = "teacher_#{current_user.id}-dashboard"
    # Re-render the course row to reset the button state
    Turbo::StreamsChannel.broadcast_replace_to(
      channel,
      target: course,
      partial: "admin/courses/course",
      locals: { course: course }
    )

    # Broadcast an error message via Turbo Streams
    Turbo::StreamsChannel.broadcast_update_to(
      channel,
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
  end
end
