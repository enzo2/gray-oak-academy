module LlmSchemas
  class KeyObservationsSchema < OpenAI::BaseModel
    required :observations, OpenAI::ArrayOf[String], doc: "1-3 distinct, concise, high-value observations about the student's learning."
  end
end
