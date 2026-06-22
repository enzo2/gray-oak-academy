class ResumeCourseOutlineResearchJob < ApplicationJob
  queue_as :agent

  def perform(course_id:, user_id:, permission_granted:, source: "course_edit")
    current_user = User.find(user_id)
    course = Course.find(course_id)
    failure_phase = "initialize"
    client = nil
    stateless_loop = nil

    permission = ActiveModel::Type::Boolean.new.cast(permission_granted)
    raise OpenAiError, "Teacher permission is required before applying research updates." unless permission

    validate_resume_prerequisites!(course)

    course.update!(
      outline_research_stage: "applying_guidance_updates",
      outline_research_error: nil,
      outline_research: clear_apply_completion_fields(course.outline_research_hash)
    )
    broadcast_editor_state(course, current_user)

    run_id = course.outline_research_run_id.presence || SecureRandom.uuid
    if CourseOutlineResearchStubService.enabled?
      run_stub_apply_phase(course: course, current_user: current_user, source: source, run_id: run_id)
      return
    end

    executor = CourseResearchToolExecutor.new(course: course, current_user: current_user)
    client = OpenaiResponsesService.new(
      current_user: current_user,
      flow_tools: executor.tool_definitions,
      enable_tools: false,
      reasoning_model: true,
      store: true,
      agent_run: true,
      agent_run_require_stateful: false
    )

    max_tool_turns = AppSetting.background_agent_max_tool_turns
    raise OpenAiError, "Background agent max tool turns is not configured. Set it in App Settings." unless max_tool_turns.present?

    stateful_supported = !client.respond_to?(:stateful_supported?) || client.stateful_supported?
    stateless_loop = ResponsesAgentLoop.new(client: client) unless stateful_supported
    response_hash = submit_initial_resume_prompt(
      client: client,
      course: course,
      run_id: run_id,
      source: source,
      previous_response_id: course.outline_research_response_id,
      stateless_loop: stateless_loop
    )

    turns = 0
    failure_phase = "apply_with_tools"
    loop do
      function_calls = Array(response_hash["output"]).select { |item| item["type"].to_s == "function_call" }
      break if function_calls.blank?

      turns += 1
      if turns > max_tool_turns
        raise OpenAiError, "Outline research apply run exceeded tool-call limit (#{max_tool_turns})."
      end

      outputs = function_calls.map { |function_call| executor.execute(function_call) }
      tool_metadata = run_metadata(
        run_id: run_id,
        source: source,
        course: course,
        teacher_id: current_user.id,
        phase: "tool_turn"
      )
      response_hash = if stateless_loop
        stateless_loop.continue_with_tool_outputs(outputs: outputs, metadata: tool_metadata)
      else
        continue_run(
          client: client,
          input: outputs,
          previous_response_id: response_hash["id"],
          metadata: tool_metadata
        )
      end
    end

    final_status = response_hash["status"].to_s
    if final_status != "completed"
      raise OpenAiError, "Outline research apply run failed with status '#{final_status}'."
    end

    final_agent_summary = extract_output_text(response_hash)
    course.update!(
      outline_research_stage: "completed",
      outline_research_error: nil,
      outline_research: merge_apply_completion_summary(
        outline_research: course.outline_research_hash,
        summary_md: final_agent_summary
      ),
      outline_research_run_id: run_id,
      outline_research_response_id: response_hash["id"].to_s
    )
    Rails.logger.info(
      "ResumeCourseOutlineResearchJob completed course=#{course.id} run_id=#{run_id} turns=#{turns} " \
      "reasoning_fallback=#{stateless_loop&.reasoning_fallback_used ? true : false}"
    )
    emit_analytics_event(
      Events::CourseOutlineResearchApplyCompleted,
      course: course,
      current_user: current_user,
      source: source,
      stage: "completed",
      run_id: run_id.to_s,
      response_id: response_hash["id"].to_s,
      tool_turns: turns.to_i
    )
    broadcast_editor_state(course, current_user)
  rescue StandardError => e
    Rails.logger.error(
      "ResumeCourseOutlineResearchJob failed for course=#{course_id} " \
      "reasoning_fallback=#{stateless_loop&.reasoning_fallback_used ? true : false}: #{e.message}"
    )
    client&.mark_current_agent_run_failed(error_message: e.message, response_hash: response_hash)
    course&.update(
      outline_research_stage: "failed",
      outline_research_error: "Failed to apply outline research guidance: #{e.message}"
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
    broadcast_editor_state(course, current_user) if current_user.present? && course.present?
    raise
  end

  private

  def run_stub_apply_phase(course:, current_user:, source:, run_id:)
    executor = CourseResearchToolExecutor.new(course: course, current_user: current_user)
    function_result = executor.execute(
      {
        "type" => "function_call",
        "name" => "apply_course_research_update",
        "call_id" => "stub_apply_#{SecureRandom.hex(6)}",
        "arguments" => CourseOutlineResearchStubService.apply_update_payload(course: course).to_json
      }
    )

    if function_result[:output].to_s.start_with?("Tool execution error:")
      raise OpenAiError, function_result[:output]
    end

    course.reload
    response_id = "stub_apply_resp_#{SecureRandom.hex(6)}"
    final_agent_summary = CourseOutlineResearchStubService.apply_summary_markdown
    course.update!(
      outline_research_stage: "completed",
      outline_research_error: nil,
      outline_research: merge_apply_completion_summary(
        outline_research: course.outline_research_hash,
        summary_md: final_agent_summary
      ),
      outline_research_run_id: run_id,
      outline_research_response_id: response_id
    )
    emit_analytics_event(
      Events::CourseOutlineResearchApplyCompleted,
      course: course,
      current_user: current_user,
      source: source,
      stage: "completed",
      run_id: run_id.to_s,
      response_id: response_id.to_s,
      tool_turns: 1
    )
    broadcast_editor_state(course, current_user)
  end

  def submit_initial_resume_prompt(client:, course:, run_id:, source:, previous_response_id:, stateless_loop: nil)
    prompt = build_resume_prompt(course)
    metadata = run_metadata(
      run_id: run_id,
      source: source,
      course: course,
      teacher_id: course.teacher_id,
      phase: "submitted"
    )
    if stateless_loop
      return stateless_loop.start(messages: [ { role: "user", content: prompt } ], metadata: metadata)
    end

    raise OpenAiError, "No previous response id is available to resume outline research run." if previous_response_id.to_s.blank?

    submitted = client.complete(
      [ { role: "user", content: prompt } ],
      previous_response_id: previous_response_id,
      background: true,
      metadata: metadata
    )

    response_id = submitted["id"].to_s
    raise OpenAiError, "Responses API did not return a response id when resuming outline research." if response_id.blank?

    client.wait_for_response(response_id, timeout_seconds: 900, poll_interval_seconds: 2)
  end

  def continue_run(client:, input:, previous_response_id:, metadata:)
    submitted = client.complete(
      nil,
      input: input,
      previous_response_id: previous_response_id,
      background: true,
      metadata: metadata
    )
    response_id = submitted["id"].to_s
    raise OpenAiError, "Responses API did not return a response id while continuing outline research apply run." if response_id.blank?

    client.wait_for_response(response_id, timeout_seconds: 900, poll_interval_seconds: 2)
  end

  def clear_apply_completion_fields(outline_research)
    payload = outline_research.is_a?(Hash) ? outline_research.deep_dup : {}
    payload.except("apply_agent_summary_md", "apply_completed_at")
  end

  def merge_apply_completion_summary(outline_research:, summary_md:)
    payload = clear_apply_completion_fields(outline_research)
    return payload if summary_md.blank?

    payload.merge(
      "apply_agent_summary_md" => summary_md,
      "apply_completed_at" => Time.current.iso8601
    )
  end

  def extract_output_text(response_hash)
    Array(response_hash["output"]).flat_map do |item|
      next [] unless item["type"].to_s == "message"

      Array(item["content"]).filter_map do |content|
        next unless content["type"].to_s == "output_text"

        content["text"].to_s
      end
    end.map(&:strip).reject(&:blank?).join("\n\n")
  end

  def build_resume_prompt(course)
    answers = course.outline_guidance_answers_hash
    question_text = Array(course.outline_guidance_questions).map do |question|
      question_hash = question.is_a?(Hash) ? question : {}
      id = question_hash["id"].to_s
      prompt = question_hash["question"].to_s
      answer = formatted_teacher_answer(question_hash: question_hash, raw_answer: answers[id])
      "- #{id}: #{prompt}\n  Teacher answer: #{answer}"
    end.join("\n")

    Prompt.get_prompt(category: "apply_course_outline_research", user: course.teacher)
      .gsub("{title}", course.title.to_s)
      .gsub("{summary}", course.summary.to_s)
      .gsub("{grade_level}", course.grade_level.to_s)
      .gsub("{outline}", course.outline.to_json)
      .gsub("{outline_guidance_report_md}", course.outline_guidance_report_md.to_s)
      .gsub("{outline_research}", course.outline_research.to_json)
      .gsub("{additional_comments}", course.outline_guidance_additional_comments.presence || "None.")
      .gsub("{teacher_answers}", question_text)
  end

  def run_metadata(run_id:, source:, course:, teacher_id:, phase:)
    AgentRunMetadata.build(
      run_id: run_id,
      run_type: "outline_research_apply",
      teacher_id: teacher_id,
      course_id: course.id,
      source: source.to_s,
      phase: phase
    )
  end

  def formatted_teacher_answer(question_hash:, raw_answer:)
    payload = parse_teacher_answer(raw_answer)
    choice = payload["choice"].to_s.upcase

    case choice
    when "A", "B", "C"
      choice_label = question_choice_label(question_hash, choice)
      "Choice #{choice}: #{choice_label}."
    when "OTHER"
      other_text = payload["other_text"].to_s.strip
      return "No response provided." if other_text.blank?

      "Other: #{other_text}"
    else
      "No response provided."
    end
  end

  def parse_teacher_answer(raw_answer)
    case raw_answer
    when Hash
      raw_answer.deep_stringify_keys
    when String
      raw = raw_answer.to_s
      return {} if raw.blank?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : {}
    else
      {}
    end
  rescue JSON::ParserError
    {}
  end

  def question_choice_label(question_hash, key)
    defaults = {
      "A" => "Keep current direction",
      "B" => "Adopt research recommendations",
      "C" => "Blend both approaches",
      "OTHER" => "Custom response"
    }
    choices = question_hash["choices"].is_a?(Hash) ? question_hash["choices"] : {}
    label = choices[key].to_s.strip
    label = choices[key.downcase].to_s.strip if label.blank?
    label.presence || defaults[key]
  end

  def validate_resume_prerequisites!(course)
    if course.unanswered_research_question_ids.any?
      raise OpenAiError, "All research questions must be answered before resuming."
    end
  end

  def broadcast_editor_state(course, current_user)
    CourseOutlineResearchBroadcasts.broadcast_editor_state(course: course, current_user: current_user)
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
    Rails.logger.error("ResumeCourseOutlineResearchJob analytics event failed course=#{course&.id}: #{e.message}")
  end
end
