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
  enum :access, { student: "student", admin: "admin", superuser: "superuser" }, prefix: true
  validates :access, presence: true
  validate :valid_specifications

  def for_llm
    # return the tool in OpenAI format
    {
      "type" => "function",
      "function" => specifications
    }
  end

  def self.enabled_for_user(user)
    allowed = if user.role_student?
      where(access: :student)
    elsif user.role_admin?
      where(access: [ :student, :admin ])
    elsif user.role_superuser?
      all
    else
      # Default to no access for unknown roles
      none
    end
    # Remove the image generation tool unless the image gen LLM is set up in AppSetting
    AppSetting.image_generation_configured? ? allowed : allowed.where.not(name: "Generate_Image")
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
