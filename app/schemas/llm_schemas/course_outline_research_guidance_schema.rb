module LlmSchemas
  class CourseOutlineResearchChoiceSetSchema < OpenAI::BaseModel
    required :a, String
    required :b, String
    required :c, String
    required :other, String
  end

  class CourseOutlineResearchQuestionSchema < OpenAI::BaseModel
    required :id, String
    required :question, String
    required :choices, CourseOutlineResearchChoiceSetSchema
  end

  class CourseOutlineResearchGuidanceSchema < OpenAI::BaseModel
    required :report_markdown, String
    required :research_questions, OpenAI::ArrayOf[CourseOutlineResearchQuestionSchema]
  end
end
