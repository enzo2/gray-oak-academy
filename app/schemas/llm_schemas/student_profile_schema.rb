module LlmSchemas
  class StudentProfileSchema < OpenAI::BaseModel
    required :current_snapshot, String, doc: "A concise summary of where the student currently stands academically and developmentally."
    required :learning_patterns, OpenAI::ArrayOf[String], doc: "Observed patterns in how this student learns best (or struggles)."
    required :current_strengths, OpenAI::ArrayOf[String], doc: "Areas where the student currently demonstrates proficiency or positive momentum."
    required :areas_for_focus, OpenAI::ArrayOf[String], doc: "Areas that currently need attention, review, or different approaches."
    required :effective_approaches, OpenAI::ArrayOf[String], doc: "Teaching methods, formats, or approaches that have proven effective."
    required :approaches_to_avoid, OpenAI::ArrayOf[String], doc: "Methods or approaches that have been ineffective or counterproductive."
    required :recommendations, OpenAI::ArrayOf[String], doc: "Specific, actionable recommendations for upcoming lessons or curriculum planning."
  end
end
