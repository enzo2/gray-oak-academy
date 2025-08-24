class Tool < ApplicationRecord
  # Tool specifications must be valid according to the OpenAI function calling spec
  # with name, description, parameters, and optional strict_mode.
  # Parameters is an object whose whose properties each include type and description.
  # Type may be string, array, number, boolean, integer, object, enum, anyOf
  # To use strict mode, include "required" array in parameters, and list all of the parameters.
  #
  # tool.name and tool.description are virtual columns derived from specifications["name"] and specifications["description"],
  # so specifications is the only column needed.

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
