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
      openai_api = app_setting&.openai_agent_supported_api
      unless openai_api&.api_access_token.present?
        return {
          tool_calls: tool_calls,
          tool_call_summary: tool_call_summary,
          output_text: "",
          response_json: "",
          error: "OpenAI shared API token is not configured in App Settings."
        }
      end

      service = OpenaiResponsesService.new(
        current_user: current_user,
        access_token: openai_api.api_access_token,
        base_uri: openai_api.api_base_uri,
        model: run[:model].presence || app_setting.openai_agent_model,
        log_completion: false,
        store: false
      )

      response = service.retrieve_response(run[:response_id])

      {
        tool_calls: tool_calls,
        tool_call_summary: tool_call_summary,
        output_text: extract_output_text(response),
        response_json: JSON.pretty_generate(response)
      }
    rescue OpenAiError => e
      {
        tool_calls: tool_calls,
        tool_call_summary: tool_call_summary,
        output_text: "",
        response_json: "",
        error: e.message
      }
    rescue StandardError => e
      Rails.logger.error "Failed to fetch run trace for #{run[:response_id]}: #{e.message}"
      {
        tool_calls: tool_calls,
        tool_call_summary: tool_call_summary,
        output_text: "",
        response_json: "",
        error: "Failed to fetch run trace: #{e.message}"
      }
    end

    def extract_output_text(response)
      Array(response["output"]).flat_map do |item|
        next [] unless item["type"].to_s == "message"

        Array(item["content"]).filter_map do |part|
          part["text"] if part["type"].to_s == "output_text"
        end
      end.join("\n\n")
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
