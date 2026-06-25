require "json/repair"

class ProposeResourcesJob < ApplicationJob
  include BackgroundAgentJob

  queue_as :agent
  include Rails.application.routes.url_helpers
  HIGH_TOOL_CALL_WARNING_THRESHOLD = 80
  RESOURCES_SCHEMA = {
    type: "object",
    properties: {
      suggested_resources: {
        type: "array",
        items: {
          type: "object",
          properties: {
            type: { type: "string" },
            description: { type: "string" }
          },
          required: [ "type", "description" ],
          additionalProperties: false
        }
      }
    },
    required: [ "suggested_resources" ],
    additionalProperties: false
  }.freeze

  def perform(lesson_plan_id:, user_id:, track_stage: true, raise_on_error: false, source: "propose_resources", skip_user_codex: false)
    current_user = User.find(user_id)
    lesson_plan = LessonPlan.find(lesson_plan_id)
    authorize_teacher_access!(current_user, lesson_plan)
    run_id = SecureRandom.uuid
    turns = 0
    total_tool_calls = 0
    high_tool_call_warning_notified = false
    response_hash = nil
    pending_retryable_tool_errors = []
    retry_prompt_sent = false
    client = nil
    executor = nil
    stateless_loop = nil
    lesson_plan.update!(status: "draft") if lesson_plan.status_published?

    set_generation_state(lesson_plan, "proposing_resources", nil) if track_stage
    broadcast_refresh(current_user)

    prompt = build_prompt(lesson_plan, current_user)
    messages = [ { role: "user", content: prompt } ]
    Rails.logger.info(
      "ProposeResourcesJob start source=#{source} lesson_plan=#{lesson_plan.id} teacher_id=#{current_user.id} prompt_chars=#{prompt.to_s.length}"
    )

    executor = ProposeResourcesToolExecutor.new(lesson_plan: lesson_plan, current_user: current_user)
    client = OpenaiResponsesService.for_agent_run(
      user: current_user,
      flow_tools: executor.tool_definitions,
      enable_tools: false,
      reasoning_model: true,
      store: true,
      agent_run_require_stateful: false,
      skip_user_codex: skip_user_codex
    )

    stateful_supported = !client.respond_to?(:stateful_supported?) || client.stateful_supported?
    stateless_loop = ResponsesAgentLoop.new(client: client) unless stateful_supported
    initial_metadata = run_metadata(
      run_id: run_id,
      current_user: current_user,
      lesson_plan: lesson_plan,
      source: source,
      phase: "submitted"
    )
    response_hash = if stateless_loop
      stateless_loop.start(messages: messages, metadata: initial_metadata)
    else
      complete_and_capture(client, messages: messages, metadata: initial_metadata)
    end
    max_tool_turns = AppSetting.background_agent_max_tool_turns
    raise OpenAiError, "Background agent max tool turns is not configured. Set it in App Settings." unless max_tool_turns.present?

    loop do
      function_calls = Array(response_hash["output"]).select { |item| item["type"].to_s == "function_call" }
      if function_calls.blank?
        if pending_retryable_tool_errors.present? && !retry_prompt_sent
          retry_prompt_sent = true
          retry_prompt = build_tool_error_retry_prompt(pending_retryable_tool_errors)
          retry_metadata = run_metadata(
            run_id: run_id,
            current_user: current_user,
            lesson_plan: lesson_plan,
            source: source,
            phase: "retry",
            retry_reason: "tool_error"
          )
          response_hash = if stateless_loop
            stateless_loop.continue_with_user_message(content: retry_prompt, metadata: retry_metadata)
          else
            complete_and_capture(
              client,
              messages: [ { role: "user", content: retry_prompt } ],
              previous_response_id: response_hash["id"],
              metadata: retry_metadata
            )
          end
          next
        end

        break
      end

      turns += 1
      if turns > max_tool_turns
        raise OpenAiError, "Resource proposal exceeded tool-call limit (#{max_tool_turns}). " \
          "observed_turns=#{turns} total_tool_calls=#{total_tool_calls}"
      end

      total_tool_calls += function_calls.size

      outputs = function_calls.map { |fc| executor.execute(fc) }
      pending_retryable_tool_errors = extract_retryable_tool_errors(outputs)
      retry_prompt_sent = false if pending_retryable_tool_errors.blank?
      run_model = client.respond_to?(:model) ? client.model : AppSetting.settings&.background_agent_model
      high_tool_call_warning_notified = log_turn_diagnostics(
        lesson_plan: lesson_plan,
        teacher: current_user,
        model: run_model,
        response_id: response_hash["id"],
        turn: turns,
        function_calls: function_calls,
        outputs: outputs,
        total_tool_calls: total_tool_calls,
        warning_notified: high_tool_call_warning_notified,
        source: source
      )
      tool_metadata = run_metadata(
        run_id: run_id,
        current_user: current_user,
        lesson_plan: lesson_plan,
        source: source,
        phase: "tool_turn"
      )
      response_hash = if stateless_loop
        stateless_loop.continue_with_tool_outputs(outputs: outputs, metadata: tool_metadata)
      else
        complete_and_capture(
          client,
          input: outputs,
          previous_response_id: response_hash["id"],
          metadata: tool_metadata
        )
      end
    end

    parsed = parse_output(client.output_text(response_hash))
    validate_output(parsed)
    suggested_resources = Array(parsed["suggested_resources"]).map do |item|
      { item["type"] => item["description"] }
    end

    lesson_plan.update!(
      suggested_resources: suggested_resources
    )
    Rails.logger.info(
      "ProposeResourcesJob completed source=#{source} lesson_plan=#{lesson_plan.id} turns=#{turns} total_tool_calls=#{total_tool_calls} " \
      "suggested_resources=#{suggested_resources.size} reasoning_fallback=#{stateless_loop&.reasoning_fallback_used ? true : false}"
    )
    set_generation_state(lesson_plan, "completed", nil) if track_stage
    broadcast_refresh(current_user)
    true
  rescue ActiveRecord::RecordNotFound
    raise
  rescue BackgroundAgentConfigResolver::TransientOauthError => e
    if oauth_retries_exhausted?
      handle_failure(
        e,
        lesson_plan: lesson_plan,
        current_user: current_user,
        source: source,
        track_stage: track_stage,
        client: client,
        response_hash: response_hash,
        stateless_loop: stateless_loop,
        turns: turns,
        total_tool_calls: total_tool_calls
      )
    end
    raise
  rescue BackgroundAgentConfigResolver::CodexUsageLimitError => e
    if codex_fallback_available?(skip_user_codex: skip_user_codex)
      Rails.logger.warn(
        "ProposeResourcesJob Codex usage limit reached; re-running on shared provider lesson_plan=#{lesson_plan&.id}"
      )
      ProposeResourcesJob.perform_later(
        lesson_plan_id: lesson_plan_id,
        user_id: user_id,
        track_stage: track_stage,
        source: source,
        skip_user_codex: true
      )
      return false
    end
    handle_failure(
      e,
      lesson_plan: lesson_plan,
      current_user: current_user,
      source: source,
      track_stage: track_stage,
      client: client,
      response_hash: response_hash,
      stateless_loop: stateless_loop,
      turns: turns,
      total_tool_calls: total_tool_calls
    )
    raise if raise_on_error
    false
  rescue StandardError => e
    handle_failure(
      e,
      lesson_plan: lesson_plan,
      current_user: current_user,
      source: source,
      track_stage: track_stage,
      client: client,
      response_hash: response_hash,
      stateless_loop: stateless_loop,
      turns: turns,
      total_tool_calls: total_tool_calls
    )
    raise if raise_on_error
    false
  ensure
    executor&.cleanup_tempfiles
  end


  private

  def handle_failure(error, lesson_plan:, current_user:, source:, track_stage:, client:, response_hash:, stateless_loop:, turns:, total_tool_calls:)
    Rails.logger.error(
      "ProposeResourcesJob failed source=#{source} lesson_plan=#{lesson_plan&.id} turns=#{turns} total_tool_calls=#{total_tool_calls} " \
      "last_response_id=#{response_hash&.dig('id')} reasoning_fallback=#{stateless_loop&.reasoning_fallback_used ? true : false} error=#{error.message}"
    )
    client&.mark_current_agent_run_failed(error_message: error.message, response_hash: response_hash)
    set_generation_state(lesson_plan, "failed", "Failed to propose resources: #{error.message}") if track_stage && lesson_plan.present?

    broadcast_refresh(current_user) if current_user.present?
  end

  def authorize_teacher_access!(current_user, lesson_plan)
    owner_id = lesson_plan.lesson.course.teacher_id
    return if current_user.role_teacher? && (current_user.role_superuser? || owner_id == current_user.id)

    raise ActiveRecord::RecordNotFound
  end

  def complete_and_capture(client, messages: nil, input: nil, previous_response_id: nil, metadata: nil)
    submitted = client.complete(
      messages,
      input: input,
      previous_response_id: previous_response_id,
      background: true,
      metadata: metadata
    )
    response_id = submitted["id"].to_s
    raise OpenAiError, "Responses API did not return a response id for background execution." if response_id.blank?

    response_hash = client.wait_for_response(
      response_id,
      timeout_seconds: 900,
      poll_interval_seconds: 2
    )
    raise OpenAiError, "Responses API did not return a valid response payload." if response_hash.blank?
    status = response_hash["status"].to_s
    if status != "completed"
      raise OpenAiError, "Responses API resource proposal run failed with status '#{status}': #{extract_response_error(response_hash)}"
    end

    response_hash
  end

  def extract_response_error(response_hash)
    error = response_hash["error"]
    return "Unknown error" if error.blank?
    return error.to_s unless error.is_a?(Hash)

    error["message"].presence || error["code"].presence || "Unknown error"
  end

  def run_metadata(run_id:, current_user:, lesson_plan:, source:, phase: "submitted", retry_reason: nil)
    AgentRunMetadata.build(
      run_id: run_id,
      run_type: "propose_resources",
      teacher_id: current_user.id,
      lesson_plan_id: lesson_plan.id,
      source: source,
      phase: phase,
      retry_reason: retry_reason
    )
  end

  def extract_retryable_tool_errors(outputs)
    Array(outputs).filter_map do |output|
      message = (output[:output] || output["output"]).to_s
      next unless message.start_with?("Tool execution error:")

      message.delete_prefix("Tool execution error:").strip.truncate(220)
    end.uniq
  end

  def build_tool_error_retry_prompt(errors)
    formatted_errors = errors.first(3).map { |error| "- #{error}" }.join("\n")
    <<~PROMPT
      One or more tool calls failed.
      Please address the tool errors below and take another pass before finalizing suggested_resources.
      Retry the relevant tool calls when needed.
      #{formatted_errors}
    PROMPT
  end

  def parse_output(content)
    raise OpenAiError, "Resource proposal response was empty." if content.blank?

    code_block_json = content.scan(/```(?:json)?\s*([\s\S]*?)\s*```/i).last&.first
    match_json = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
    json_content = code_block_json.presence || match_json.presence || content.strip
    raise OpenAiError, "No JSON object found in resource proposal output." if json_content.blank?

    JSON.parse(json_content)
  rescue JSON::ParserError
    begin
      repaired = JSON.repair(json_content)
      JSON.parse(repaired)
    rescue JSON::ParserError, JSON::JSONRepairError => e
      raise OpenAiError, "Invalid JSON from resource proposal: #{e.message}"
    end
  end

  def validate_output(parsed)
    schemer = JSONSchemer.schema(RESOURCES_SCHEMA)
    return if schemer.valid?(parsed)

    errors = schemer.validate(parsed).map { |err| err["error"] }.join(", ")
    raise OpenAiError, "Invalid resource proposal schema: #{errors}"
  end

  def build_prompt(lesson_plan, current_user)
    lesson = lesson_plan.lesson
    course = lesson.course

    Prompt.get_prompt(category: "suggest_resources", user: current_user)
      .gsub("{title}", "#{lesson.position}. #{lesson.title}")
      .gsub("{goals}", lesson.goals)
      .gsub("{approx_duration_min}", lesson.approx_duration_min.to_s)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_title}", course.title)
      .gsub("{lesson_plan_content}", lesson_plan.content.to_json)
      .gsub("{suggested_resources}", lesson_plan.suggested_resources.to_json)
      .gsub("{linked_resources}", lesson_plan.resources.format_collection)
  end

  def set_generation_state(lesson_plan, stage, error)
    lesson_plan.update!(generation_stage: stage, generation_error: error)
  end

  def broadcast_refresh(current_user)
    channel = "teacher_#{current_user.id}-dashboard"
    Turbo::StreamsChannel.broadcast_refresh_to(channel)
  end

  def log_turn_diagnostics(lesson_plan:, teacher:, model:, response_id:, turn:, function_calls:, outputs:, total_tool_calls:, warning_notified:, source:)
    names_by_count = function_calls.map { |call| call["name"].to_s }.tally
    sample_arguments = function_calls.first(3).map do |function_call|
      "#{function_call['name']}(#{function_call['arguments'].to_s.squish.truncate(110)})"
    end.join(" | ")

    Rails.logger.info(
      "ProposeResourcesJob turn source=#{source} lesson_plan=#{lesson_plan.id} turn=#{turn} calls_this_turn=#{function_calls.size} " \
      "tool_counts=#{names_by_count} total_tool_calls=#{total_tool_calls} " \
      "sample_calls=#{sample_arguments.presence || 'none'}"
    )

    return warning_notified if total_tool_calls < HIGH_TOOL_CALL_WARNING_THRESHOLD

    Rails.logger.warn(
      "ProposeResourcesJob high-volume warning source=#{source} lesson_plan=#{lesson_plan.id} turn=#{turn} " \
      "total_tool_calls=#{total_tool_calls}"
    )
    return true if warning_notified

    notify_high_tool_call_warning!(
      lesson_plan: lesson_plan,
      teacher: teacher,
      model: model,
      response_id: response_id,
      turn: turn,
      total_tool_calls: total_tool_calls,
      source: source
    )
    true
  end

  def notify_high_tool_call_warning!(lesson_plan:, teacher:, model:, response_id:, turn:, total_tool_calls:, source:)
    superuser_ids = User.role_superuser.pluck(:id)
    return if superuser_ids.empty?

    run_id = response_id.to_s.presence || "unknown_run"
    trace_link = response_id.to_s.present? ? admin_agent_runs_path(trace_response_id: response_id.to_s) : admin_agent_runs_path
    Rails.event.notify(Events::AgentRunHighToolCallWarning.new(
      recipient_ids: superuser_ids,
      link: trace_link,
      run_id: run_id,
      response_id: response_id.to_s,
      teacher_name: teacher.name,
      teacher_id: teacher.id,
      model: model.to_s,
      source: source.to_s,
      lesson_plan_id: lesson_plan.id,
      turns: turn,
      total_tool_calls: total_tool_calls,
      warning_threshold: HIGH_TOOL_CALL_WARNING_THRESHOLD
    ))
  rescue StandardError => e
    Rails.logger.error "Failed to notify high tool-call warning for lesson_plan=#{lesson_plan.id}: #{e.message}"
  end
end
