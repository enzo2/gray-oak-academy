module LlmSchemas
  class MergedMemoriesSchema < OpenAI::BaseModel
    required :new_memories, OpenAI::ArrayOf[String]
    required :replacement_ids, OpenAI::ArrayOf[Integer]
  end
end
