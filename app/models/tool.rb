class Tool < ApplicationRecord
  belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :tools, optional: true

  validates :name, presence: true
  validates :description, presence: true, length: { minimum: 10 }
  validates :specifications, presence: true
  validate :valid_specifications

  private

  def for_llm
    # return the specifications wrapped in a function object
    {
      type: "function",
      function: specifications
    }
  end

  def valid_specifications
    schema = {
      type: "object",
      required: [ "name", "description", "parameters" ],
      properties: {
        name: { type: "string" },
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
        example_usage: { type: "string" },
        constraints: {
          type: "array",
          items: {
            type: "object",
            required: [ "type", "description" ],
            properties: {
              type: { type: "string" },
              description: { type: "string" }
            }
          }
        }
      }
    }

    errors.add(:specifications, "is not valid") unless JSONSchemer.schema(schema).valid?(specifications)
  end
end
