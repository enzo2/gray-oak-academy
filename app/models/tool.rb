class Tool < ApplicationRecord
  belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :tools, optional: true

  validates :name, presence: true
  validates :description, presence: true, length: { minimum: 10 }
  validates :specifications, presence: true
  validate :valid_specifications

  private

  def valid_specifications
    schema = {
      type: "object",
      required: [ "name", "description", "parameters", "strict_mode", "return_type", "example_usage", "constraints" ],
      properties: {
        name: { type: "string" },
        description: { type: "string" },
        parameters: {
          type: "array",
          items: {
            type: "object",
            required: [ "name", "type", "description", "required" ],
            properties: {
              name: { type: "string" },
              type: { type: "string" },
              description: { type: "string" },
              required: { type: "boolean" }
            }
          }
        },
        strict_mode: { type: "boolean" },
        return_type: { type: "string" },
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

# Example specification:
=begin
{
  "type": "iframe_update",
  "allowed_types": ["iframe_update", "student_assessment_query", "lesson_summary_query", "save_lesson_summary", "save_student_assessment"],
  "parameters": [
    {
      "name": "url",
      "type": "string",
      "description": "The URL to load in the iframe",
      "required": true
    }
  ],
  "return_type": "boolean",
  "example_usage": "update_iframe_url('https://example.com/educational-video')",
  "constraints": [
    {
      "type": "url_whitelist",
      "description": "Only allowed to use URLs that were specified in the lesson plan. May adjust for correct URI formatting or query parameters."
    }
  ]
}
=end
