class DelegateToFrontierLlmJob < ApplicationJob
  queue_as :default

  def perform(teacher, prompt)
    unless teacher.role_teacher?
      raise "Permission denied: this tool is only available to teachers."
    end
    # Validate that the teacher has a reasoning LLM configured
    unless teacher.setting.reasoning_model_name.present?
      raise "No reasoning LLM configured. Please configure a reasoning model in settings before using this tool."
    end

    task_system_prompt = Prompt.get_prompt(category: "generative_guidelines", user: teacher) +
                        "\n\n" +
                         Prompt.get_prompt(category: "delegate_to_frontier_llm", user: teacher)

    # Prepare messages for the LLM
    messages = [ { role: "user", content: prompt } ]

    begin
      # Make the LLM request using reasoning model (non-streaming)
      client = OpenaiApiService.new(
        current_user: teacher,
        reasoning_model: true,
        task_system_prompt: task_system_prompt
      )

      client.complete(messages)

    rescue StandardError => e
      Rails.logger.error "Error in DelegateToFrontierLlmJob: #{e.message}"
      raise e # Re-raise to be handled by the tool handler
    end
  end
end
