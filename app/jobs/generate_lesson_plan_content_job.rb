class GenerateLessonPlanContentJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(lesson_plan, *, **) { "lesson-plan-content-#{lesson_plan.id}" }, duration: 10.minutes

  CONTENT_SCHEMA = {
    strict: true,
    name: "Lesson_Plan",
    description: "A detailed lesson plan content and strategy outline.",
    schema: LlmSchemas::LessonPlanSchema.to_json_schema.deep_stringify_keys
  }

  NATIVE_WEB_SEARCH_TOOLS_BY_HOST = {
    "api.openai.com" => [ { type: "web_search" } ],
    "chatgpt.com" => [ { type: "web_search" } ],
    "openrouter.ai" => [ { type: "openrouter:web_search" } ],
    "api.x.ai" => [ { type: "web_search" } ]
  }.freeze

  def perform(lesson_plan, current_user, steering_guidance: nil, track_stage: true, raise_on_error: false)
    lesson = lesson_plan.lesson
    course = lesson.course
    set_generation_state(lesson_plan, "generating_content", nil) if track_stage
    # Treat the run as a revision only when existing content is paired with an
    # explicit instruction. Non-UI callers (e.g. TeacherAgent's generate_content)
    # pass no steering and rely on generate_content REPLACING existing content.
    revising = lesson_plan.content.present? && steering_guidance.to_s.strip.present?
    revision_context = revising ? build_revision_context(lesson_plan, steering_guidance) : ""
    prompt_template = Prompt.get_prompt(category: "generate_lesson_plan", user: current_user)
    prompt_template = append_revision_context_placeholder(prompt_template) if revision_context.present?

    customized_prompt = prompt_template
      .gsub("{title}", "#{lesson.position}. #{lesson.title}")
      .gsub("{goals}", lesson.goals)
      .gsub("{approx_duration_min}", lesson.approx_duration_min.to_s)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_title}", course.title)
      .gsub("{linked_resources}", lesson.lesson_plan.resources.format_collection)
      .gsub("{other_lessons}", lesson.course.lessons.where.not(id: lesson.id).map { |l| "#{l.position}. #{l.title}" }.join(", "))
      .gsub("{revision_context}", revision_context)

    if steering_guidance.present? && revision_context.blank?
      customized_prompt += <<~PROMPT

        Additional steering from the supervising teacher for this run:
        #{steering_guidance}
      PROMPT
    end

    web_search_tools = native_web_search_tools(current_user)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: customized_prompt } ]

    begin
      # Make the LLM request
      client = LlmServiceRouting.build_completion_client(
        current_user: current_user,
        reasoning_model: true,
        store: false,
        provider_native_tools: web_search_tools
      )

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
        suggested_resources: extracted_suggested_resources,
        generation_metadata: web_search_tools.present? ? extract_generation_research(client) : {}
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

  # Native web search is hosted by the upstream provider inside the same
  # structured-output call. Tool names are provider-specific, so only enable
  # hosts with a known Responses-compatible search tool.
  def native_web_search_tools(current_user)
    host = LlmServiceRouting.effective_llm_api_host_for(user: current_user)
    NATIVE_WEB_SEARCH_TOOLS_BY_HOST[host]
  end

  # Pull the searches the model ran and the sources it cited out of the raw
  # Responses payload (kept on the client as last_response_hash) so the teacher
  # can see what informed the draft. Best-effort: queries are reliably present;
  # cited sources may be sparse under structured output.
  def extract_generation_research(client)
    return {} unless client.respond_to?(:last_response_hash)

    response_hash = client.last_response_hash
    return {} if response_hash.blank?

    output = Array(response_hash["output"])

    searches = output.filter_map do |item|
      next unless item["type"].to_s == "web_search_call"

      item.dig("action", "query").to_s.strip.presence
    end.uniq

    # OpenAI/Codex emit cited sources as url_citation annotations on message
    # content. xAI emits these too, AND also exposes a top-level "citations"
    # array of URL strings for every source the agent consulted — fold both in.
    annotation_sources = output.flat_map do |item|
      next [] unless item["type"].to_s == "message"

      Array(item["content"]).flat_map do |part|
        Array(part["annotations"]).filter_map do |annotation|
          next unless annotation["type"].to_s == "url_citation"

          url = annotation["url"].to_s.strip
          next if url.blank?

          { "url" => url, "title" => annotation["title"].to_s.strip.presence }
        end
      end
    end

    citation_sources = Array(response_hash["citations"]).filter_map do |citation|
      url, title =
        if citation.is_a?(Hash)
          [ citation["url"].to_s.strip, citation["title"].to_s.strip.presence ]
        else
          [ citation.to_s.strip, nil ]
        end
      next if url.blank?

      { "url" => url, "title" => title }
    end

    # Annotations carry titles, so list them first; uniq keeps the richer entry.
    sources = (annotation_sources + citation_sources).uniq { |source| source["url"] }

    { "searches" => searches, "sources" => sources }
  end

  def append_revision_context_placeholder(prompt_template)
    return prompt_template if prompt_template.include?("{revision_context}")

    "#{prompt_template}\n\n{revision_context}"
  end

  def build_revision_context(lesson_plan, steering_guidance)
    revision_instruction = steering_guidance.to_s.strip
    current_plan = {
      "lesson_plan" => normalize_plan_items(lesson_plan.content, value_key: "details"),
      "suggested_resources" => normalize_plan_items(lesson_plan.suggested_resources, value_key: "description")
    }

    <<~PROMPT

      Current saved lesson plan JSON:
      #{JSON.pretty_generate(current_plan)}

      Revision instruction from the supervising teacher:
      #{revision_instruction}

      Revise the current saved plan according to the instruction. Return the full updated lesson_plan array and the full updated suggested_resources array, preserving useful existing content and changing only what is needed.
    PROMPT
  end

  def normalize_plan_items(items, value_key:)
    Array(items).filter_map do |item|
      next unless item.respond_to?(:to_h)

      item_hash = item.to_h.stringify_keys
      next if item_hash.blank?

      if item_hash.key?("type") && item_hash.key?(value_key)
        { "type" => item_hash["type"], value_key => item_hash[value_key] }
      else
        type, value = item_hash.first
        { "type" => type, value_key => value }
      end
    end
  end

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
      locals: { lesson: lesson_plan.lesson, lesson_plan: lesson_plan, current_user: current_user }
    )
  end
end
