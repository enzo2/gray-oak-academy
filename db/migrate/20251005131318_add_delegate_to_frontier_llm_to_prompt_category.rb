class AddDelegateToFrontierLlmToPromptCategory < ActiveRecord::Migration[8.0]
  def up
    add_enum_value :prompt_category, "delegate_to_frontier_llm", after: "tool_usage"
  end
end
