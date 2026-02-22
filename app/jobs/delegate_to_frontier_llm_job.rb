class DelegateToFrontierLlmJob < ApplicationJob
  queue_as :default
  include Rails.application.routes.url_helpers

  def perform(teacher, prompt, source: "tool_call")
    unless teacher.role_teacher?
      raise "Permission denied: this tool is only available to teachers."
    end

    task_system_prompt = Prompt.get_prompt(category: "generative_guidelines", user: teacher) +
                        "\n\n" +
                         Prompt.get_prompt(category: "delegate_to_frontier_llm", user: teacher)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: prompt } ]

    app_setting = AppSetting.settings
    return run_legacy_delegate(teacher, task_system_prompt, messages) unless app_setting&.openai_agent_enabled?

    run_id = SecureRandom.uuid
    started_at = Time.current
    model = app_setting.openai_agent_model
    use_exa_search = app_setting.exa_enabled?

    response_id = nil
    failure_notified = false

    begin
      function_call_adapter = ResponsesFunctionCallAdapter.new(
        current_user: teacher,
        exa_enabled: use_exa_search,
        allow_app_tools: false
      )

      client = OpenaiResponsesService.new(
        current_user: teacher,
        task_system_prompt: task_system_prompt,
        enable_tools: false,
        provider_native_tools: function_call_adapter.delegate_provider_native_tools,
        flow_tools: function_call_adapter.delegate_flow_tools,
        store: true,
        log_completion: true,
        agent_run: true
      )

      submitted = client.complete(
        messages,
        background: true,
        metadata: run_metadata(
          teacher: teacher,
          run_id: run_id,
          source: source,
          phase: "submitted"
        )
      )

      response_id = submitted["id"]

      final_response = client.wait_for_response(
        response_id,
        timeout_seconds: 900,
        poll_interval_seconds: 2
      )

      max_tool_turns = AppSetting.openai_agent_max_tool_turns
      raise OpenAiError, "Background agent max tool turns is not configured. Set it in App Settings." unless max_tool_turns.present?
      turns = 0
      loop do
        status = final_response["status"].to_s
        break unless status == "completed"

        function_calls = function_call_adapter.function_calls(final_response)
        break if function_calls.blank?

        turns += 1
        if turns > max_tool_turns
          raise OpenAiError, "Agent run exceeded tool-call limit (#{max_tool_turns})."
        end

        tool_outputs = function_call_adapter.function_call_outputs(function_calls)

        continued = client.complete(
          input: tool_outputs,
          previous_response_id: final_response["id"],
          background: true,
          metadata: run_metadata(
            teacher: teacher,
            run_id: run_id,
            source: source,
            phase: "tool_turn"
          )
        )
        response_id = continued["id"]
        final_response = client.wait_for_response(
          response_id,
          timeout_seconds: 900,
          poll_interval_seconds: 2
        )
      end

      response_id = final_response["id"]
      status = final_response["status"].to_s
      if status == "completed"
        result = client.output_text(final_response)
        raise OpenAiError, "Agent run completed with empty output." if result.blank?
        return result
      end

      error_message = extract_response_error(final_response)
      notify_failed(
        run_id: run_id,
        response_id: response_id,
        teacher: teacher,
        model: model,
        source: source,
        prompt: prompt,
        started_at: started_at,
        error_message: "Run status: #{status}. #{error_message}"
      )
      failure_notified = true
      raise OpenAiError, "Agent run failed with status '#{status}': #{error_message}"

    rescue StandardError => e
      Rails.logger.error "Error in DelegateToFrontierLlmJob: #{e.message}"
      unless failure_notified
        notify_failed(
          run_id: run_id,
          response_id: response_id,
          teacher: teacher,
          model: model,
          source: source,
          prompt: prompt,
          started_at: started_at,
          error_message: e.message
        )
      end
      raise e # Re-raise to be handled by the tool handler
    end
  end

  private

  def run_legacy_delegate(teacher, task_system_prompt, messages)
    # Validate that the teacher has a reasoning LLM configured
    unless teacher.setting.reasoning_model_name.present?
      raise "No reasoning LLM configured. Please configure a reasoning model in settings before using this tool."
    end

    client = OpenaiApiService.new(
      current_user: teacher,
      reasoning_model: true,
      task_system_prompt: task_system_prompt
    )
    client.complete(messages)
  end

  def notify_failed(run_id:, response_id:, teacher:, model:, source:, prompt:, started_at:, error_message:)
    return if run_id.blank?

    superuser_ids = User.role_superuser.pluck(:id)
    return if superuser_ids.empty?

    Rails.event.notify(Events::AgentRunFailed.new(
      recipient_ids: superuser_ids,
      link: admin_agent_runs_path,
      run_id: run_id,
      response_id: response_id.to_s,
      teacher_name: teacher.name,
      teacher_id: teacher.id,
      model: model.to_s,
      source: source.to_s,
      task_preview: truncate_prompt(prompt),
      duration_seconds: (Time.current - started_at).round(1),
      error_message: error_message.to_s.truncate(500)
    ))
  rescue StandardError => e
    Rails.logger.error "Failed to notify failed agent run #{run_id}: #{e.message}"
  end

  def extract_response_error(response_hash)
    error = response_hash["error"]
    return "Unknown error" if error.blank?
    return error.to_s unless error.is_a?(Hash)

    error["message"].presence || error["code"].presence || "Unknown error"
  end

  def truncate_prompt(prompt)
    prompt.to_s.squish.truncate(220)
  end

  def run_metadata(teacher:, run_id:, source:, phase:)
    AgentRunMetadata.build(
      run_id: run_id,
      run_type: "delegate_to_frontier_llm",
      teacher_id: teacher.id,
      source: source.to_s,
      phase: phase
    )
  end
end
