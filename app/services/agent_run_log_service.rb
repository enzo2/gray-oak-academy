class AgentRunLogService
  MAX_LOGS = 500

  def initialize(app_setting: AppSetting.settings)
    @app_setting = app_setting
  end

  def list(limit: 300)
    read_logs.first(limit)
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
      submitted_at: Time.current.iso8601
    )
  end

  def record_completed(run_id:, response_id:, response_hash:, started_at:)
    metrics = output_metrics(response_hash)
    upsert_run!(
      run_id: run_id,
      response_id: response_id,
      status: "completed",
      finished_at: Time.current.iso8601,
      duration_seconds: (Time.current - started_at).round(1),
      assistant_turns: metrics[:assistant_turns],
      tool_call_count: metrics[:tool_call_count],
      reasoning_item_count: metrics[:reasoning_item_count],
      output_item_count: metrics[:output_item_count]
    )
  end

  def record_failed(run_id:, response_id:, response_hash: nil, started_at:, error_message:)
    metrics = output_metrics(response_hash || {})
    upsert_run!(
      run_id: run_id,
      response_id: response_id,
      status: "failed",
      finished_at: Time.current.iso8601,
      duration_seconds: (Time.current - started_at).round(1),
      assistant_turns: metrics[:assistant_turns],
      tool_call_count: metrics[:tool_call_count],
      reasoning_item_count: metrics[:reasoning_item_count],
      output_item_count: metrics[:output_item_count],
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

  def output_metrics(response_hash)
    items = Array(response_hash["output"])

    {
      assistant_turns: items.count { |item| item["type"].to_s == "message" },
      tool_call_count: items.count { |item| tool_call_item?(item["type"]) },
      reasoning_item_count: items.count { |item| item["type"].to_s == "reasoning" },
      output_item_count: items.size
    }
  end

  def tool_call_item?(type)
    type = type.to_s
    type == "function_call" || type.end_with?("_call")
  end
end
