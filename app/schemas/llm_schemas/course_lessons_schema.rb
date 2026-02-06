module LlmSchemas
  class CourseLessonSchema < OpenAI::BaseModel
    required :title, String
    required :goals, String
    required :duration, Integer
  end

  class CourseLessonsSchema < OpenAI::BaseModel
    required :lessons, OpenAI::ArrayOf[CourseLessonSchema]
  end
end
