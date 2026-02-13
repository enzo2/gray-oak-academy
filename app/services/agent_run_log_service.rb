class AgentRunLogService
  MAX_LOGS = 500
  MAX_TASK_PROMPT_CHARS = 50_000

  def initialize(app_setting: AppSetting.settings)
    @app_setting = app_setting
  end

  def list(limit: 300)
    read_logs.first(limit)
  end

  def clear!
    return unless @app_setting

    @app_setting.with_lock do
      log = (@app_setting.log || {}).deep_dup
      log["agent_run_logs"] = []
      settings = @app_setting.settings.deep_dup
      settings.delete("agent_run_logs")
      @app_setting.update!(log: log, settings: settings)
    end
  end

  def record_submitted(run_id:, response_id:, teacher:, model:, source:, prompt:)
    upsert_run!(
      run_id: run_id,
      response_id: response_id,
      status: "submitted",
      teacher_name: teacher.name,
      teacher_id: teacher.id,
      model: model.to_s,
      source: source.to_s,
      task_preview: truncate_prompt(prompt),
      task_prompt: normalize_task_prompt(prompt),
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
      tool_calls: normalize_tool_calls(tool_calls)
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
      error_message: error_message.to_s.truncate(500)
    )
  end

  private

  def upsert_run!(attrs)
    return unless @app_setting

    @app_setting.with_lock do
      log = (@app_setting.log || {}).deep_dup
      logs = Array(log["agent_run_logs"])
      run_id = attrs[:run_id].to_s

      index = logs.index { |entry| entry["run_id"].to_s == run_id }
      if index
        logs[index] = logs[index].merge(attrs.deep_stringify_keys)
      else
        logs.unshift(attrs.deep_stringify_keys)
      end

      logs = logs.first(MAX_LOGS)
      settings = @app_setting.settings.deep_dup
      settings.delete("agent_run_logs")
      @app_setting.update!(log: log.merge("agent_run_logs" => logs), settings: settings)
    end
  end

  def read_logs
    return [] unless @app_setting
    Array((@app_setting.log || {})["agent_run_logs"]).map(&:deep_symbolize_keys)
  end

  def truncate_prompt(prompt)
    prompt.to_s.squish.truncate(220)
  end

  def normalize_task_prompt(prompt)
    prompt.to_s.first(MAX_TASK_PROMPT_CHARS)
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
