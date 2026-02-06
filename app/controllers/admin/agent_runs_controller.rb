module Admin
  class AgentRunsController < Admin::BaseController
    before_action :require_superuser

    def index
      @runs = AgentRunLogService.new.list(limit: 500)
      @runs = @runs.sort_by { |run| run[:submitted_at].presence || run[:finished_at].presence || "" }.reverse.first(300)
      load_reasoning_trace
    end

    private

    def load_reasoning_trace
      @trace_response_id = params[:trace_response_id].to_s.presence
      return unless @trace_response_id.present?

      @trace_run = @runs.find { |run| run[:response_id] == @trace_response_id }
      return unless @trace_run

      @trace_data = fetch_reasoning_trace(@trace_run)
    end

    def fetch_reasoning_trace(run)
      app_setting = AppSetting.settings
      openai_api = app_setting&.openai_agent_supported_api
      unless openai_api&.api_access_token.present?
        return { error: "OpenAI shared API token is not configured in App Settings." }
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
      output_items = Array(response["output"])
      reasoning_items = output_items.select { |item| item["type"].to_s == "reasoning" }
      output_type_counts = output_items.each_with_object(Hash.new(0)) do |item, counts|
        counts[item["type"].to_s] += 1
      end

      {
        output_items_json: output_items.present? ? JSON.pretty_generate(output_items) : "",
        output_type_counts: output_type_counts,
        output_text: extract_output_text(response),
        summary_text: extract_reasoning_summary(reasoning_items),
        reasoning_json: reasoning_items.present? ? JSON.pretty_generate(reasoning_items) : "",
        response_json: JSON.pretty_generate(response)
      }
    rescue OpenAiError => e
      { error: e.message }
    rescue StandardError => e
      Rails.logger.error "Failed to fetch reasoning trace for #{run[:response_id]}: #{e.message}"
      { error: "Failed to fetch reasoning trace: #{e.message}" }
    end

    def extract_reasoning_summary(reasoning_items)
      Array(reasoning_items).flat_map do |item|
        Array(item["summary"]).map do |summary_part|
          summary_part["text"] || summary_part["summary"] || summary_part.to_json
        end
      end.join("\n")
    end

    def extract_output_text(response)
      Array(response["output"]).flat_map do |item|
        next [] unless item["type"].to_s == "message"

        Array(item["content"]).filter_map do |part|
          part["text"] if part["type"].to_s == "output_text"
        end
      end.join("\n\n")
    end
  end
end
