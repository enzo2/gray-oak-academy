require "json/repair"

class EnrichCourseOutlineJob < ApplicationJob
  include BackgroundAgentJob

  queue_as :agent

  EXA_OUTPUT_SCHEMA = {
    type: "object",
    properties: {
      source_anchors: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            url: { type: "string" },
            excerpt: { type: "string" },
            highlights: {
              type: "array",
              items: { type: "string" }
            },
            notes: { type: "string" }
          },
          required: [ "title", "url", "excerpt", "highlights", "notes" ],
          additionalProperties: false
        }
      },
      coverage_gaps: {
        type: "array",
        items: { type: "string" }
      },
      factual_notes: {
        type: "array",
        items: { type: "string" }
      },
      alternative_approaches: {
        type: "array",
        items: { type: "string" }
      }
    },
    required: [ "source_anchors", "coverage_gaps", "factual_notes", "alternative_approaches" ],
    additionalProperties: false
  }.freeze

  PHASE1_SCHEMA = {
    strict: true,
    name: "Course_Outline_Research_Guidance",
    description: "Teacher-facing markdown report and at most five guiding questions about outline improvements.",
    schema: LlmSchemas::CourseOutlineResearchGuidanceSchema.to_json_schema.deep_stringify_keys
  }.freeze

  def perform(course_id:, user_id:, source: "course_edit", conversation_id: nil, skip_user_codex: false)
    current_user = User.find(user_id)
    course = Course.find(course_id)
    authorize_teacher_access!(current_user, course)
    failure_phase = "initialize"

    course.update!(outline_research_stage: "researching_outline", outline_research_error: nil)
    update_outline_research_progress!(
      course,
      message: "Preparing outline research...",
      detail: "Building the research brief from this course outline.",
      step: 1,
      total_steps: 4
    )
    broadcast_editor_state(course, current_user)
    if CourseOutlineResearchStubService.enabled?
      run_stub_pipeline(
        course: course,
        current_user: current_user,
        source: source,
        conversation_id: conversation_id
      )
      return
    end

    failure_phase = "exa_research"
    research_payload = reusable_exa_research_payload(course)
    if research_payload
      Rails.logger.info(
        "EnrichCourseOutlineJob reusing completed Exa research course=#{course.id} " \
        "research_id=#{research_payload['research_id'].presence || 'unknown'}"
      )
    else
      research_payload = run_exa_research(course: course, current_user: current_user)
      emit_analytics_event(
        Events::CourseOutlineResearchExaCompleted,
        course: course,
        current_user: current_user,
        source: source,
        stage: "researching_outline",
        research_id: research_payload["research_id"].to_s,
        source_anchor_count: Array(research_payload["source_anchors"]).size,
        coverage_gap_count: Array(research_payload["coverage_gaps"]).size,
        factual_note_count: Array(research_payload["factual_notes"]).size,
        alternative_approach_count: Array(research_payload["alternative_approaches"]).size
      )
    end

    course.update!(
      outline_research: research_payload,
      outline_research_stage: "generating_guidance_questions",
      outline_research_error: nil
    )
    update_outline_research_progress!(
      course,
      message: "Research complete; writing guidance...",
      detail: "#{Array(research_payload['source_anchors']).size} source anchors found. Generating the teacher report and questions.",
      step: 3,
      total_steps: 4
    )
    broadcast_editor_state(course, current_user)

    run_id = course.outline_research_run_id.presence || SecureRandom.uuid
    failure_phase = "guidance_generation"
    guidance_payload, response_id = generate_guidance_questions(
      course: course,
      current_user: current_user,
      run_id: run_id,
      source: source,
      skip_user_codex: skip_user_codex
    )

    course.update!(
      outline_guidance_report_md: guidance_payload.fetch("report_markdown"),
      outline_guidance_questions: guidance_payload.fetch("research_questions"),
      outline_guidance_answers: {},
      outline_research_stage: "awaiting_teacher_input",
      outline_research_error: nil,
      outline_research_run_id: run_id,
      outline_research_response_id: response_id
    )
    update_outline_research_progress!(
      course,
      message: "Research guidance is ready.",
      detail: "Review the report, answer the teacher questions, and resume the apply phase when ready.",
      step: 4,
      total_steps: 4
    )
    emit_analytics_event(
      Events::CourseOutlineResearchGuidanceReady,
      course: course,
      current_user: current_user,
      source: source,
      stage: "awaiting_teacher_input",
      run_id: run_id.to_s,
      response_id: response_id.to_s,
      question_count: Array(guidance_payload["research_questions"]).size,
      source_anchor_count: Array(course.outline_research_hash["source_anchors"]).size
    )
    broadcast_chalkboard_research_input(course: course, conversation_id: conversation_id)
    broadcast_editor_state(course, current_user)
  rescue ActiveRecord::RecordNotFound
    raise
  rescue BackgroundAgentConfigResolver::TransientOauthError => e
    handle_failure(e, course: course, current_user: current_user, source: source, failure_phase: failure_phase) if oauth_retries_exhausted?
    raise
  rescue BackgroundAgentConfigResolver::CodexFallbackError => e
    if codex_fallback_available?(skip_user_codex: skip_user_codex)
      Rails.logger.warn(
        "EnrichCourseOutlineJob Codex provider failed recoverably (#{e.class.name.demodulize}); " \
        "re-running on shared provider course=#{course&.id}"
      )
      EnrichCourseOutlineJob.perform_later(
        course_id: course_id,
        user_id: user_id,
        source: source,
        conversation_id: conversation_id,
        skip_user_codex: true
      )
      return
    end
    handle_failure(e, course: course, current_user: current_user, source: source, failure_phase: failure_phase)
    raise
  rescue StandardError => e
    handle_failure(e, course: course, current_user: current_user, source: source, failure_phase: failure_phase)
    raise
  end

  private

  def handle_failure(error, course:, current_user:, source:, failure_phase:)
    Rails.logger.error("EnrichCourseOutlineJob failed for course=#{course&.id}: #{error.message}")
    course&.update(
      outline_research_stage: "failed",
      outline_research_error: "Failed to run outline research: #{error.message}"
    )
    if course.present?
      begin
        update_outline_research_progress!(
          course,
          message: "Outline research failed.",
          detail: error.message.to_s.truncate(180)
        )
      rescue StandardError => progress_error
        Rails.logger.error("EnrichCourseOutlineJob failed to persist failure progress course=#{course.id}: #{progress_error.message}")
      end
    end
    emit_analytics_event(
      Events::CourseOutlineResearchPipelineFailed,
      course: course,
      current_user: current_user,
      source: source,
      stage: course&.outline_research_stage || "failed",
      phase: failure_phase,
      run_id: course&.outline_research_run_id.to_s,
      response_id: course&.outline_research_response_id.to_s,
      error_message: error.message.to_s.truncate(500)
    )
    broadcast_editor_state(course, current_user) if current_user.present? && course.present?
  end

  def authorize_teacher_access!(current_user, course)
    return if current_user.role_teacher? && (current_user.role_superuser? || course.teacher_id == current_user.id)

    raise ActiveRecord::RecordNotFound
  end

  def reusable_exa_research_payload(course)
    payload = course.outline_research_hash
    return unless payload.dig("exa_research", "status").to_s.casecmp?("completed")
    return unless research_payload?(payload)

    payload.deep_dup
  end

  def run_stub_pipeline(course:, current_user:, source:, conversation_id:)
    research_payload = CourseOutlineResearchStubService.research_payload(course: course)
    emit_analytics_event(
      Events::CourseOutlineResearchExaCompleted,
      course: course,
      current_user: current_user,
      source: source,
      stage: "researching_outline",
      research_id: research_payload["research_id"].to_s,
      source_anchor_count: Array(research_payload["source_anchors"]).size,
      coverage_gap_count: Array(research_payload["coverage_gaps"]).size,
      factual_note_count: Array(research_payload["factual_notes"]).size,
      alternative_approach_count: Array(research_payload["alternative_approaches"]).size
    )

    course.update!(
      outline_research: research_payload,
      outline_research_stage: "generating_guidance_questions",
      outline_research_error: nil
    )
    update_outline_research_progress!(
      course,
      message: "Research complete; writing guidance...",
      detail: "#{Array(research_payload['source_anchors']).size} source anchors found. Generating the teacher report and questions.",
      step: 3,
      total_steps: 4
    )
    broadcast_editor_state(course, current_user)

    run_id = course.outline_research_run_id.presence || SecureRandom.uuid
    guidance_payload = CourseOutlineResearchStubService.guidance_payload(course: course)
    response_id = "stub_guidance_resp_#{SecureRandom.hex(6)}"
    prefilled_answers = CourseOutlineResearchStubService.prefilled_guidance_answers(
      guidance_payload.fetch("research_questions")
    )

    course.update!(
      outline_guidance_report_md: guidance_payload.fetch("report_markdown"),
      outline_guidance_questions: guidance_payload.fetch("research_questions"),
      outline_guidance_answers: prefilled_answers,
      outline_research_stage: "awaiting_teacher_input",
      outline_research_error: nil,
      outline_research_run_id: run_id,
      outline_research_response_id: response_id
    )
    update_outline_research_progress!(
      course,
      message: "Research guidance is ready.",
      detail: "Review the report, answer the teacher questions, and resume the apply phase when ready.",
      step: 4,
      total_steps: 4
    )
    emit_analytics_event(
      Events::CourseOutlineResearchGuidanceReady,
      course: course,
      current_user: current_user,
      source: source,
      stage: "awaiting_teacher_input",
      run_id: run_id.to_s,
      response_id: response_id.to_s,
      question_count: Array(guidance_payload["research_questions"]).size,
      source_anchor_count: Array(course.outline_research_hash["source_anchors"]).size
    )
    broadcast_chalkboard_research_input(course: course, conversation_id: conversation_id)
    broadcast_editor_state(course, current_user)
  end

  def run_exa_research(course:, current_user:)
    prompt = Prompt.get_prompt(category: "research_course_outline", user: current_user)
      .gsub("{title}", course.title.to_s)
      .gsub("{summary}", course.summary.to_s)
      .gsub("{grade_level}", course.grade_level.to_s)
      .gsub("{outline}", course.outline.to_json)

    exa = ExaApiService.new(current_user: current_user)
    started_at = Time.current
    Rails.logger.info("EnrichCourseOutlineJob Exa deep research started course=#{course.id}")
    persist_exa_research_progress!(
      course: course,
      research_id: nil,
      poll_count: 0,
      response: { "status" => "running" }
    )
    update_outline_research_progress!(
      course,
      message: "Searching and synthesizing sources...",
      detail: "Exa deep-reasoning search is gathering evidence for the outline.",
      step: 2,
      total_steps: 4
    )
    broadcast_editor_state(course, current_user)

    response = exa.deep_research(query: prompt, output_schema: EXA_OUTPUT_SCHEMA)
    research_id = response["id"].to_s.presence || response["requestId"].to_s.presence || response.dig("output", "id").to_s.presence
    status = response["status"].to_s.downcase
    Rails.logger.info("EnrichCourseOutlineJob Exa deep research finished course=#{course.id} research_id=#{research_id.presence || 'unknown'} status=#{status.presence || 'completed'}")
    if status.present? && status != "completed"
      raise OpenAiError, "Exa outline research finished with status '#{status}'."
    end

    normalized = normalize_outline_research(extract_research_output(response))
    normalized.merge(
      "research_id" => research_id,
      "generated_at" => Time.current.iso8601,
      "exa_research" => exa_research_meta(
        research_id: research_id,
        started_at: started_at,
        poll_count: 0,
        response: response.merge("status" => status.presence || "completed")
      )
    )
  end

  def extract_research_output(response)
    payload = find_research_payload(response.dig("output", "content"))
    payload ||= find_research_payload(response["output"])
    payload ||= find_research_payload(response)
    payload || {}
  end

  def normalize_outline_research(raw_payload)
    payload = raw_payload.is_a?(Hash) ? raw_payload.deep_dup : {}
    anchors = Array(payload_value(payload, "source_anchors", "sourceAnchors")).map.with_index do |anchor, idx|
      anchor_hash = anchor.is_a?(Hash) ? anchor : {}
      {
        "id" => payload_value(anchor_hash, "id", "anchorId").to_s.presence || "anchor_#{idx + 1}",
        "title" => payload_value(anchor_hash, "title").to_s,
        "url" => payload_value(anchor_hash, "url", "sourceUrl").to_s,
        "excerpt" => payload_value(anchor_hash, "excerpt", "summary").to_s,
        "highlights" => Array(payload_value(anchor_hash, "highlights", "key_points", "keyPoints", "bulletPoints")).map(&:to_s),
        "notes" => payload_value(anchor_hash, "notes", "note").to_s
      }
    end

    {
      "source_anchors" => anchors,
      "coverage_gaps" => Array(payload_value(payload, "coverage_gaps", "coverageGaps")).map(&:to_s),
      "factual_notes" => Array(payload_value(payload, "factual_notes", "factualNotes")).map(&:to_s),
      "alternative_approaches" => Array(payload_value(payload, "alternative_approaches", "alternativeApproaches")).map(&:to_s)
    }
  end

  def find_research_payload(node)
    case node
    when Hash
      return node if research_payload?(node)

      node.each_value do |value|
        found = find_research_payload(value)
        return found if found.present?
      end
    when Array
      node.each do |value|
        found = find_research_payload(value)
        return found if found.present?
      end
    when String
      parsed = try_parse_json(node)
      return parsed if parsed.is_a?(Hash) && research_payload?(parsed)
    end

    nil
  end

  def research_payload?(payload)
    return false unless payload.is_a?(Hash)

    keys = payload.keys.map(&:to_s)
    (keys & %w[
      source_anchors
      sourceAnchors
      coverage_gaps
      coverageGaps
      factual_notes
      factualNotes
      alternative_approaches
      alternativeApproaches
    ]).any?
  end

  def payload_value(hash, *keys)
    return nil unless hash.is_a?(Hash)

    keys.each do |key|
      return hash[key] if hash.key?(key)

      string_key = key.to_s
      return hash[string_key] if hash.key?(string_key)
      return hash[string_key.to_sym] if hash.key?(string_key.to_sym)
    end

    nil
  end

  def try_parse_json(content)
    parse_json(content)
  rescue OpenAiError
    nil
  end

  def generate_guidance_questions(course:, current_user:, run_id:, source:, skip_user_codex: false)
    prompt = Prompt.get_prompt(category: "analyze_course_outline_research", user: current_user)
      .gsub("{title}", course.title.to_s)
      .gsub("{summary}", course.summary.to_s)
      .gsub("{grade_level}", course.grade_level.to_s)
      .gsub("{outline}", course.outline.to_json)
      .gsub("{outline_research}", course.outline_research.to_json)

    client = OpenaiResponsesService.for_agent_run(
      user: current_user,
      reasoning_model: true,
      enable_tools: false,
      store: true,
      agent_run_require_stateful: false,
      skip_user_codex: skip_user_codex
    )

    submitted = client.complete(
      [ { role: "user", content: prompt } ],
      response_format: {
        type: "json_schema",
        json_schema: PHASE1_SCHEMA.slice(:name, :schema, :strict)
      },
      background: true,
      metadata: AgentRunMetadata.build(
        run_id: run_id,
        run_type: "outline_research_guidance",
        teacher_id: current_user.id,
        course_id: course.id,
        source: source.to_s,
        phase: "submitted"
      )
    )
    response_id = submitted["id"].to_s
    raise OpenAiError, "Responses API did not return a response id for outline research guidance." if response_id.blank?

    response_hash = client.wait_for_response(response_id, timeout_seconds: 900, poll_interval_seconds: 2)
    status = response_hash["status"].to_s
    if status != "completed"
      raise OpenAiError, "Outline research guidance run failed with status '#{status}'."
    end

    parsed = parse_json(client.output_text(response_hash))
    report = parsed["report_markdown"].to_s
    questions = normalize_questions(parsed["research_questions"])
    if report.blank?
      raise OpenAiError, "Outline research guidance report was blank."
    end
    if questions.empty?
      raise OpenAiError, "Outline research guidance returned no questions."
    end

    [ { "report_markdown" => report, "research_questions" => questions }, response_hash["id"].to_s ]
  end

  def normalize_questions(raw_questions)
    used_ids = {}

    Array(raw_questions).first(5).map.with_index do |question, idx|
      question_hash = question.is_a?(Hash) ? question : {}
      text = question_hash["question"].to_s.strip
      next if text.blank?
      id = deduplicated_question_id(question_hash["id"], idx: idx, used_ids: used_ids)

      { "id" => id, "question" => text, "choices" => normalize_question_choices(question_hash["choices"]) }
    end.compact
  end

  def deduplicated_question_id(raw_id, idx:, used_ids:)
    base_id = raw_id.to_s.strip.presence || "q#{idx + 1}"
    candidate = base_id
    suffix = 2

    while used_ids[candidate]
      candidate = "#{base_id}_#{suffix}"
      suffix += 1
    end

    used_ids[candidate] = true
    candidate
  end

  def normalize_question_choices(raw_choices)
    choices_hash = raw_choices.is_a?(Hash) ? raw_choices : {}
    normalized = {
      "A" => choices_hash["A"].to_s.presence || choices_hash["a"].to_s.presence,
      "B" => choices_hash["B"].to_s.presence || choices_hash["b"].to_s.presence,
      "C" => choices_hash["C"].to_s.presence || choices_hash["c"].to_s.presence,
      "OTHER" => choices_hash["OTHER"].to_s.presence || choices_hash["other"].to_s.presence
    }

    normalized["A"] ||= "Keep current direction"
    normalized["B"] ||= "Adopt research recommendations"
    normalized["C"] ||= "Blend both approaches"
    normalized["OTHER"] ||= "Custom response"
    normalized
  end

  def persist_exa_research_progress!(course:, research_id:, poll_count:, response:)
    existing = course.outline_research_hash.deep_dup
    existing["exa_research"] = exa_research_meta(
      research_id: research_id,
      started_at: existing.dig("exa_research", "started_at"),
      poll_count: poll_count,
      response: response
    )
    course.update_columns(outline_research: existing, updated_at: Time.current)
  end

  def update_outline_research_progress!(course, message:, detail: nil, step: nil, total_steps: nil)
    course.update_outline_research_progress!(
      message: message,
      detail: detail,
      step: step,
      total_steps: total_steps
    )
  end

  def exa_research_meta(research_id:, started_at:, poll_count:, response:)
    status = response["status"].to_s
    {
      "research_id" => research_id.to_s,
      "status" => status,
      "api" => "search",
      "type" => ExaApiService::DEEP_RESEARCH_SEARCH_TYPE,
      "poll_count" => poll_count.to_i,
      "started_at" => (started_at.is_a?(String) ? started_at : started_at&.iso8601) || Time.current.iso8601,
      "last_checked_at" => Time.current.iso8601,
      "provider_updated_at" => response["updatedAt"].to_s.presence || response["updated_at"].to_s.presence,
      "grounding" => response.dig("output", "grounding"),
      "message" => response["message"].to_s.presence || response.dig("error", "message").to_s.presence
    }.compact
  end

  def parse_json(content)
    raise OpenAiError, "Outline research response was empty." if content.blank?

    code_block_json = content.scan(/```(?:json)?\s*([\s\S]*?)\s*```/i).last&.first
    match_json = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
    json_content = code_block_json.presence || match_json.presence || content.strip
    raise OpenAiError, "No JSON object found in outline research output." if json_content.blank?

    JSON.parse(json_content)
  rescue JSON::ParserError
    repaired = JSON.repair(json_content)
    JSON.parse(repaired)
  rescue JSON::ParserError, JSON::JSONRepairError => e
    raise OpenAiError, "Invalid JSON from outline research output: #{e.message}"
  end

  def broadcast_editor_state(course, current_user)
    CourseOutlineResearchBroadcasts.broadcast_editor_state(course: course, current_user: current_user)
  end

  def broadcast_chalkboard_research_input(course:, conversation_id:)
    return if conversation_id.blank?

    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    content_html = ApplicationController.render(
      partial: "admin/courses/chalkboard_research_input",
      locals: { course: course }
    )

    payload = {
      event_type: "open_push_tab",
      tab_id: "outline_research_#{course.id}_#{SecureRandom.hex(6)}",
      tab_title: "Outline Research",
      kind: "outline_research",
      content_html: content_html
    }

    Turbo::StreamsChannel.broadcast_append_to(
      "conversation_#{conversation.id}",
      target: "chalkboard_tab_inbox",
      partial: "shared/chalkboard_tab_event",
      locals: { payload: payload }
    )
  rescue StandardError => e
    Rails.logger.error("EnrichCourseOutlineJob chalkboard notification failed course=#{course&.id} conversation=#{conversation_id}: #{e.message}")
  end

  def emit_analytics_event(event_class, course:, current_user:, source:, stage:, **params)
    return if course.blank? || current_user.blank?

    Rails.event.notify(event_class.new(
      recipient_ids: [],
      link: Rails.application.routes.url_helpers.edit_admin_course_path(course),
      teacher_name: current_user.name,
      teacher_id: current_user.id,
      course_id: course.id,
      course_title: course.title.to_s,
      source: source.to_s,
      stage: stage.to_s,
      **params
    ))
  rescue StandardError => e
    Rails.logger.error("EnrichCourseOutlineJob analytics event failed course=#{course&.id}: #{e.message}")
  end
end
