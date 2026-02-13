class AddCourseResearchPromptCategories < ActiveRecord::Migration[8.1]
  def up
    add_enum_value :prompt_category, "research_course_outline", after: "generate_observations", if_not_exists: true
    add_enum_value :prompt_category, "analyze_course_outline_research", after: "research_course_outline", if_not_exists: true
    add_enum_value :prompt_category, "apply_course_outline_research", after: "analyze_course_outline_research", if_not_exists: true
  end
end
