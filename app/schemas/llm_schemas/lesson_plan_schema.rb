module LlmSchemas
  class LessonPlanStepSchema < OpenAI::BaseModel
    required :type, String
    required :details, String
  end

  class SuggestedResourceSchema < OpenAI::BaseModel
    required :type, String
    required :description, String
  end

  class LessonPlanSchema < OpenAI::BaseModel
    required :lesson_plan, OpenAI::ArrayOf[LessonPlanStepSchema]
    required :suggested_resources, OpenAI::ArrayOf[SuggestedResourceSchema], doc: "A list of suggested resources for the lesson which may need to be located, obtained or validated before use."
  end
end
