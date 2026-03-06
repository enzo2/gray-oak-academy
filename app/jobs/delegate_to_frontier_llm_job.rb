class DelegateToFrontierLlmJob < ApplicationJob
  queue_as :default

  def perform(teacher, prompt, source: "tool_call")
    unless teacher.role_teacher?
      raise "Permission denied: this tool is only available to teachers."
    end

    task_system_prompt = Prompt.get_prompt(category: "generative_guidelines", user: teacher) +
                        "\n\n" +
                         Prompt.get_prompt(category: "delegate_to_frontier_llm", user: teacher)

    messages = [ { role: "user", content: prompt } ]

    run_reasoning_delegate(teacher, task_system_prompt, messages)
  end

  private

  def run_reasoning_delegate(teacher, task_system_prompt, messages)
    client = LlmServiceRouting.build_completion_client(
      current_user: teacher,
      reasoning_model: true,
      task_system_prompt: task_system_prompt,
      store: false
    )
    client.complete(messages)
  end
end
