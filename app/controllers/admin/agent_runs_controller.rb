module Admin
  class AgentRunsController < Admin::BaseController
    before_action :require_superuser

    def index
      @runs = AgentRunLogService.new.list(limit: 500)
      @runs = @runs.sort_by { |run| run[:submitted_at].presence || run[:finished_at].presence || "" }.reverse.first(300)
      load_run_trace
    end

    def clear
      AgentRunLogService.new.clear!
      redirect_to admin_agent_runs_path, notice: "Agent run logs cleared."
    end

    private

    def load_run_trace
      @trace_response_id = params[:trace_response_id].to_s.presence
      return unless @trace_response_id.present?

      @trace_run = @runs.find { |run| run[:response_id] == @trace_response_id }
      return unless @trace_run

      @trace_data = fetch_run_trace(@trace_run)
    end

    def fetch_run_trace(run)
      tool_calls = normalize_tool_calls(run[:tool_calls])
      tool_call_summary = summarize_tool_calls(tool_calls)
      app_setting = AppSetting.settings

      service = OpenaiResponsesService.new(
        current_user: current_user,
        base_uri: run[:provider_base_uri].to_s.presence,
        model: run[:model].presence || app_setting&.openai_agent_model,
        agent_run: true,
        agent_run_require_stateful: false,
        log_completion: false,
        store: false
      )

      response = service.retrieve_response(run[:response_id])
      task_prompt = resolved_task_prompt(run: run, response: response)

      {
        tool_calls: tool_calls,
        tool_call_summary: tool_call_summary,
        task_prompt: task_prompt.to_s,
        task_preview: resolved_task_preview(run: run, response: response),
        input_text: extract_input_text(response),
        instructions_text: response["instructions"].to_s,
        output_text: extract_output_text(response),
        response_json: JSON.pretty_generate(response)
      }
    rescue OpenAiError => e
      {
        tool_calls: tool_calls,
        tool_call_summary: tool_call_summary,
        task_prompt: run[:task_prompt].to_s,
        task_preview: run[:task_preview].to_s,
        input_text: "",
        instructions_text: "",
        output_text: "",
        response_json: "",
        error: e.message
      }
    rescue StandardError => e
      Rails.logger.error "Failed to fetch run trace for #{run[:response_id]}: #{e.message}"
      {
        tool_calls: tool_calls,
        tool_call_summary: tool_call_summary,
        task_prompt: run[:task_prompt].to_s,
        task_preview: run[:task_preview].to_s,
        input_text: "",
        instructions_text: "",
        output_text: "",
        response_json: "",
        error: "Failed to fetch run trace: #{e.message}"
      }
    end

  def resolved_task_prompt(run:, response:)
    run[:task_prompt].to_s.presence || response_metadata_value(response, "task_full", "task_prompt")
  end

  def resolved_task_preview(run:, response:)
    run[:task_preview].to_s.presence || response_metadata_value(response, "task_preview")
  end

  def response_metadata_value(response, *keys)
    metadata = response["metadata"]
    return "" unless metadata.is_a?(Hash)

    keys.each do |key|
      value = metadata[key] || metadata[key.to_sym]
      return value.to_s if value.present?
    end

    ""
  end

  def extract_output_text(response)
    Array(response["output"]).flat_map do |item|
      next [] unless item["type"].to_s == "message"

        Array(item["content"]).filter_map do |part|
          part["text"] if part["type"].to_s == "output_text"
      end
    end.join("\n\n")
  end

  def extract_input_text(response)
    Array(response["input"]).flat_map do |item|
      next item.to_s unless item.is_a?(Hash)

      extract_text_from_content(item["content"])
    end.join("\n\n")
  end

  def extract_text_from_content(content)
    case content
    when String
      content
    when Array
      content.filter_map { |part| extract_text_from_content(part) }.join(" ")
    when Hash
      content["text"] || content["input_text"] || content["output_text"] || content["content"]&.to_s
    else
      content.to_s
    end
  end

    def normalize_tool_calls(tool_calls)
      Array(tool_calls).filter_map do |tool_call|
        call = tool_call.is_a?(Hash) ? tool_call.deep_symbolize_keys : {}
        response_id = call[:response_id].to_s.presence
        call_id = call[:call_id].to_s
        name = call[:name].to_s
        next if call_id.blank? && name.blank?

        {
          response_id: response_id,
          call_id: call_id,
          name: name,
          arguments_preview: call[:arguments_preview].to_s.presence,
          argument_fingerprint: call[:argument_fingerprint].to_s.presence
        }.compact
      end
    end

    def summarize_tool_calls(tool_calls)
      counts_by_name = tool_calls.each_with_object(Hash.new(0)) do |tool_call, counts|
        counts[tool_call[:name].to_s] += 1
      end

      repeated_argument_patterns = tool_calls
        .select { |tool_call| tool_call[:argument_fingerprint].present? }
        .group_by { |tool_call| [ tool_call[:name], tool_call[:argument_fingerprint] ] }
        .filter_map do |(name, fingerprint), calls|
          next if calls.size < 2

          {
            name: name,
            count: calls.size,
            arguments_preview: calls.first[:arguments_preview].presence || "(No argument preview)",
            argument_fingerprint: fingerprint
          }
        end
        .sort_by { |entry| -entry[:count] }
        .first(20)

      {
        total_calls: tool_calls.size,
        unique_tools: counts_by_name.keys.size,
        counts_by_name: counts_by_name.sort_by { |name, count| [ -count, name ] },
        repeated_argument_patterns: repeated_argument_patterns
      }
    end
  end
end
