# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Use the 1st admin user as the teacher
admin_user = User.role_admin.first

# Create a sample tool
Tool.find_or_create_by!(name: 'Iframe Update Tool') do |tool|
  tool.description = 'A tool to update the iframe URL in the student view'
  tool.teacher = admin_user
  tool.specifications = {
    name: "iframe_update",
    description: "Updates the URL of the iframe in the student view",
    parameters: [
      {
        name: "url",
        type: "string",
        description: "The URL to load in the iframe",
        required: true
      }
    ],
    strict_mode: true,
    return_type: "boolean",
    example_usage: "update_iframe_url('https://example.com/educational-video')",
    constraints: [
      {
        type: "url_whitelist",
        description: "Only allowed to use URLs that were specified in the lesson plan. May adjust for correct URI formatting or query parameters."
      }
    ]
  }
end

Prompt.find_or_create_by!(category: 'generate_lessons') do |p|
  p.title = "Default Lesson Plan Generator"
  p.teacher = admin_user
  p.prompt = <<~PROMPT
    I am designing a course titled "{title}" for grade level {grade_level} with the following summary: "{summary}".#{' '}
    Please generate a detailed course outline in JSON format where each key is a topic and each value is a brief description of that topic.#{' '}
    Don't nest beyond the key:value pairs.#{' '}
    Ensure the outline is comprehensive and suitable for the grade level.
  PROMPT
end

puts "Seed data has been created successfully!"
