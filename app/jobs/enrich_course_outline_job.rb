require "json/repair"

class EnrichCourseOutlineJob < ApplicationJob
  queue_as :default

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

  def perform(course_id:, user_id:, source: "course_edit")
    current_user = User.find(user_id)
    course = Course.find(course_id)
    failure_phase = "initialize"

    course.update!(outline_research_stage: "researching_outline", outline_research_error: nil)
    broadcast_refresh(current_user)

    failure_phase = "exa_research"
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

    course.update!(
      outline_research: research_payload,
      outline_research_stage: "generating_guidance_questions",
      outline_research_error: nil
    )
    broadcast_refresh(current_user)

    run_id = course.outline_research_run_id.presence || SecureRandom.uuid
    failure_phase = "guidance_generation"
    guidance_payload, response_id = generate_guidance_questions(
      course: course,
      current_user: current_user,
      run_id: run_id,
      source: source
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
    broadcast_refresh(current_user)
  rescue StandardError => e
    Rails.logger.error("EnrichCourseOutlineJob failed for course=#{course_id}: #{e.message}")
    course&.update(
      outline_research_stage: "failed",
      outline_research_error: "Failed to run outline research: #{e.message}"
    )
    emit_analytics_event(
      Events::CourseOutlineResearchPipelineFailed,
      course: course,
      current_user: current_user,
      source: source,
      stage: course&.outline_research_stage || "failed",
      phase: failure_phase,
      run_id: course&.outline_research_run_id.to_s,
      response_id: course&.outline_research_response_id.to_s,
      error_message: e.message.to_s.truncate(500)
    )
    broadcast_refresh(current_user) if current_user.present?
    raise
  end

  private

  def run_exa_research(course:, current_user:)
    prompt = Prompt.get_prompt(category: "research_course_outline", user: current_user)
      .gsub("{title}", course.title.to_s)
      .gsub("{summary}", course.summary.to_s)
      .gsub("{grade_level}", course.grade_level.to_s)
      .gsub("{outline}", course.outline.to_json)

    exa = ExaApiService.new(current_user: current_user)
    created = exa.create_research(instructions: prompt, output_schema: EXA_OUTPUT_SCHEMA)
    research_id = created["id"].to_s.presence || created["researchId"].to_s.presence
    started_at = Time.current
    poll_count = 0
    last_broadcast_at = Time.at(0)

    Rails.logger.info("EnrichCourseOutlineJob Exa research submitted course=#{course.id} research_id=#{research_id.presence || 'unknown'}")
    persist_exa_research_progress!(
      course: course,
      research_id: research_id,
      poll_count: poll_count,
      response: created
    )
    broadcast_refresh(current_user)

    response =
      if research_id.present?
        exa.wait_for_research(research_id: research_id, timeout_seconds: 900, poll_interval_seconds: 3) do |poll_response|
          poll_count += 1
          previous_status = course.outline_research_hash.dig("exa_research", "status").to_s
          persist_exa_research_progress!(
            course: course,
            research_id: research_id,
            poll_count: poll_count,
            response: poll_response
          )

          status = poll_response["status"].to_s
          status_changed = status.present? && status != previous_status
          should_broadcast = status_changed || (Time.current - last_broadcast_at) >= 9
          if should_broadcast
            broadcast_refresh(current_user)
            last_broadcast_at = Time.current
          end
        end
      else
        created
      end

    status = response["status"].to_s.downcase
    Rails.logger.info("EnrichCourseOutlineJob Exa research finished course=#{course.id} research_id=#{research_id.presence || response['id']} status=#{status.presence || 'unknown'} polls=#{poll_count}")
    if status.present? && status != "completed"
      raise OpenAiError, "Exa outline research finished with status '#{status}'."
    end

    normalized = normalize_outline_research(extract_research_output(response))
    normalized.merge(
      "research_id" => research_id || response["id"],
      "generated_at" => Time.current.iso8601,
      "exa_research" => exa_research_meta(
        research_id: research_id || response["id"],
        started_at: started_at,
        poll_count: poll_count,
        response: response
      )
    )
  end

  def extract_research_output(response)
    payload = find_research_payload(response["output"])
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

  def generate_guidance_questions(course:, current_user:, run_id:, source:)
    openai_config = openai_agent_config!
    prompt = Prompt.get_prompt(category: "analyze_course_outline_research", user: current_user)
      .gsub("{title}", course.title.to_s)
      .gsub("{summary}", course.summary.to_s)
      .gsub("{grade_level}", course.grade_level.to_s)
      .gsub("{outline}", course.outline.to_json)
      .gsub("{outline_research}", course.outline_research.to_json)

    client = OpenaiResponsesService.new(
      current_user: current_user,
      access_token: openai_config[:access_token],
      base_uri: openai_config[:base_uri],
      model: openai_config[:model],
      reasoning_model: true,
      enable_tools: false,
      store: true
    )

    submitted = client.complete(
      [ { role: "user", content: prompt } ],
      response_format: {
        type: "json_schema",
        json_schema: PHASE1_SCHEMA.slice(:name, :schema, :strict)
      },
      background: true,
      metadata: {
        run_id: run_id,
        run_type: "outline_research_guidance",
        teacher_id: current_user.id.to_s,
        course_id: course.id.to_s,
        source: source.to_s
      }
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

  def exa_research_meta(research_id:, started_at:, poll_count:, response:)
    status = response["status"].to_s
    {
      "research_id" => research_id.to_s,
      "status" => status,
      "poll_count" => poll_count.to_i,
      "started_at" => (started_at.is_a?(String) ? started_at : started_at&.iso8601) || Time.current.iso8601,
      "last_checked_at" => Time.current.iso8601,
      "provider_updated_at" => response["updatedAt"].to_s.presence || response["updated_at"].to_s.presence,
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

  def openai_agent_config!
    app_setting = AppSetting.settings
    raise OpenAiError, "OpenAI Agent Runs is not configured. Ask a superuser to set the OpenAI Agent model and key in App Settings." unless app_setting&.openai_agent_enabled?

    openai_api = app_setting.openai_agent_supported_api
    raise OpenAiError, "OpenAI shared API is not configured for agent runs." unless openai_api

    {
      access_token: app_setting.openai_agent_access_token,
      base_uri: openai_api.api_base_uri,
      model: app_setting.openai_agent_model
    }
  end

  def broadcast_refresh(current_user)
    Turbo::StreamsChannel.broadcast_refresh_to("teacher_#{current_user.id}-dashboard")
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
