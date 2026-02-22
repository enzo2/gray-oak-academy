class AgentRunLogService
  MAX_TASK_PROMPT_CHARS = 50_000
  UPSERT_MAX_RETRIES = 2

  def initialize
  end

  def list(limit: 300)
    AgentRun
      .order(Arel.sql("COALESCE(submitted_at, finished_at) DESC"), id: :desc)
      .limit(limit)
      .map { |run| serialize_run(run) }
  end

  def clear!
    AgentRun.delete_all
  end

  def record_submitted(run_id:, response_id:, teacher:, model:, source:, prompt:, provider_base_uri: nil, metadata_version: nil, phase: nil)
    upsert_run!(
      run_id: run_id,
      response_id: response_id,
      status: "submitted",
      teacher_name: teacher.name,
      teacher_id: teacher.id,
      model: model.to_s,
      provider_base_uri: provider_base_uri.to_s,
      source: source.to_s,
      task_preview: truncate_prompt(prompt),
      task_prompt: normalize_task_prompt(prompt),
      metadata_version: metadata_version.to_s.presence,
      phase: phase.to_s.presence || "submitted",
      submitted_at: Time.current.iso8601
    )
  end

  def record_completed(run_id:, response_id:, response_hash:, started_at:, metrics: nil, tool_calls: nil)
    metrics = normalize_metrics(metrics) || output_metrics(response_hash)
    upsert_run!(
      run_id: run_id,
      response_id: response_id,
      status: "completed",
      finished_at: Time.current.iso8601,
      duration_seconds: (Time.current - started_at).round(1),
      assistant_turns: metrics[:assistant_turns],
      tool_call_count: metrics[:tool_call_count],
      tool_turn_count: metrics[:tool_turn_count],
      reasoning_item_count: metrics[:reasoning_item_count],
      output_item_count: metrics[:output_item_count],
      tool_calls: normalize_tool_calls(tool_calls),
      phase: "completed"
    )
  end

  def record_failed(run_id:, response_id:, response_hash: nil, started_at:, error_message:, metrics: nil, tool_calls: nil)
    metrics = normalize_metrics(metrics) || output_metrics(response_hash || {})
    upsert_run!(
      run_id: run_id,
      response_id: response_id,
      status: "failed",
      finished_at: Time.current.iso8601,
      duration_seconds: (Time.current - started_at).round(1),
      assistant_turns: metrics[:assistant_turns],
      tool_call_count: metrics[:tool_call_count],
      tool_turn_count: metrics[:tool_turn_count],
      reasoning_item_count: metrics[:reasoning_item_count],
      output_item_count: metrics[:output_item_count],
      tool_calls: normalize_tool_calls(tool_calls),
      error_message: error_message.to_s.truncate(500),
      phase: "failed"
    )
  end

  private

  def upsert_run!(attrs)
    run_id = attrs[:run_id].to_s
    return if run_id.blank?

    attrs_hash = attrs.deep_stringify_keys
    retries = 0

    begin
      AgentRun.transaction do
        run = AgentRun.lock.find_by(run_id: run_id)
        run ||= AgentRun.new(run_id: run_id)
        run.assign_attributes(attrs_hash.except("run_id"))
        run.events = append_run_event(run.events, attrs_hash)
        run.save!
      end
    rescue ActiveRecord::RecordNotUnique
      retries += 1
      retry if retries <= UPSERT_MAX_RETRIES
      raise
    end
  end

  def serialize_run(run)
    run.attributes.deep_symbolize_keys
  end

  def truncate_prompt(prompt)
    redact_prompt(prompt).squish.truncate(220)
  end

  def normalize_task_prompt(prompt)
    redact_prompt(prompt).first(MAX_TASK_PROMPT_CHARS)
  end

  def append_run_event(existing_events, attrs_hash)
    events = Array(existing_events).map { |event| event.is_a?(Hash) ? event.deep_dup : nil }.compact
    event = {
      "at" => Time.current.iso8601,
      "status" => attrs_hash["status"].to_s.presence,
      "phase" => attrs_hash["phase"].to_s.presence,
      "response_id" => attrs_hash["response_id"].to_s.presence
    }.compact

    last = events.last
    signature = event.slice("status", "phase", "response_id")
    last_signature = last.is_a?(Hash) ? last.slice("status", "phase", "response_id") : {}
    events << event if signature.present? && signature != last_signature

    events.last(50)
  end

  def redact_prompt(prompt)
    redacted = prompt.to_s.dup
    redacted.gsub!(/sk-[A-Za-z0-9\-_]{20,}/, "[REDACTED_TOKEN]")
    redacted.gsub!(/((?:api[_-]?key|access[_-]?token|authorization)\s*[:=]\s*)([^\s,;]+)/i, "\\1[REDACTED]")
    redacted
  end

  def output_metrics(response_hash)
    items = Array(response_hash["output"])

    {
      assistant_turns: items.count { |item| item["type"].to_s == "message" },
      tool_call_count: items.count { |item| tool_call_item?(item["type"]) },
      tool_turn_count: items.any? { |item| tool_call_item?(item["type"]) } ? 1 : 0,
      reasoning_item_count: items.count { |item| item["type"].to_s == "reasoning" },
      output_item_count: items.size
    }
  end

  def tool_call_item?(type)
    type = type.to_s
    type == "function_call" || type.end_with?("_call")
  end

  def normalize_metrics(metrics)
    return nil unless metrics.is_a?(Hash)

    {
      assistant_turns: metrics[:assistant_turns].to_i,
      tool_call_count: metrics[:tool_call_count].to_i,
      tool_turn_count: metrics[:tool_turn_count].to_i,
      reasoning_item_count: metrics[:reasoning_item_count].to_i,
      output_item_count: metrics[:output_item_count].to_i
    }
  end

  def normalize_tool_calls(tool_calls)
    Array(tool_calls).filter_map do |tool_call|
      call = tool_call.is_a?(Hash) ? tool_call.deep_symbolize_keys : {}
      response_id = call[:response_id].to_s.presence
      call_id = call[:call_id].to_s
      name = call[:name].to_s
      next if call_id.blank? && name.blank?
      arguments_preview = call[:arguments_preview].to_s.presence
      argument_fingerprint = call[:argument_fingerprint].to_s.presence

      {
        response_id: response_id,
        call_id: call_id,
        name: name,
        arguments_preview: arguments_preview&.truncate(220),
        argument_fingerprint: argument_fingerprint
      }.compact
    end
  end
end
