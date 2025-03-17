class Tool < ApplicationRecord
  # belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :tools, optional: true

  validates :specifications, presence: true
  validates :name, uniqueness: true
  validate :valid_specifications

  def for_llm
    # return the tool in OpenAI format
    {
      "type": "function",
      "function": specifications
    }
  end

  private

  def valid_specifications
    schema = {
      type: "object",
      required: [ "name", "description", "parameters" ],
      properties: {
        name: {
          type: "string",
          pattern: "^[a-zA-Z0-9_-]{1,64}$"
        },
        description: { type: "string" },
        parameters: {
          type: "object",
          required: [ "type", "properties" ],
          properties: {
            type: { type: "string" },
            properties: {
              type: "object",
              additionalProperties: {
                type: "object",
                required: [ "type", "description" ],
                properties: {
                  type: { type: "string" },
                  description: { type: "string" }
                }
              }
            },
            required: {
              type: "array",
              items: { type: "string" }
            }
          }
        },
        strict_mode: { type: "boolean" },
        example_usage: { type: "string" }
      }
    }

    errors.add(:specifications, "is not valid") unless JSONSchemer.schema(schema).valid?(specifications)
  end
end
