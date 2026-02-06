module LlmSchemas
  class ConversationTitleSchema < OpenAI::BaseModel
    required :title, String
  end
end
