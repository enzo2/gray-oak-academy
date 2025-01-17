class AddGenerativeGuidelinesToPromptCategory < ActiveRecord::Migration[8.0]
  def up
    add_enum_value :prompt_category, "generative_guidelines", after: "tool_usage"
  end
end
