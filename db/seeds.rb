# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create a sample admin user if it doesn't exist
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

puts "Seed data has been created successfully!"
