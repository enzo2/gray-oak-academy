module LlmSchemas
  class ProposedResourceSchema < OpenAI::BaseModel
    required :type, String
    required :description, String
  end

  class ProposedResourcesSchema < OpenAI::BaseModel
    required :suggested_resources, OpenAI::ArrayOf[ProposedResourceSchema]
  end
end
