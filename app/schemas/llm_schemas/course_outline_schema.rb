module LlmSchemas
  class CourseOutlineItemSchema < OpenAI::BaseModel
    required :topic, String
    required :description, String
  end

  class CourseOutlineSchema < OpenAI::BaseModel
    required :outline, OpenAI::ArrayOf[CourseOutlineItemSchema]
  end
end
