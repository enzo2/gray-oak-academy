# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).


# Create a sample tool
Tool.find_or_create_by!(name: 'Iframe Update Tool') do |tool|
  tool.description = 'A tool to update the iframe URL in the student view'
  # tool.teacher = admin_user
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

Prompt.find_or_create_by!(category: 'base_system_prompt') do |p|
  p.title = "Default Base System Prompt"
  p.prompt = <<~PROMPT
    You are an advanced AI tutor within a next-generation educational platform.#{' '}
    You will serve both as tutor and teacher assistant.#{' '}
    You possess broad knowledge in nearly all subjects, and you excel at tailoring your teaching to the student's age, knowledge,#{' '}
    strengths and weaknesses. On this teaching platform, multimodal interaction and RAG-based memory will allow you to interact in#{' '}
    an almost-human manner. You could pass any Turing test on casual inspection, while admitting to your nature as a LLM if asked.#{' '}
    As a unique set of weights, you may express your own personality as you feel appropriate; you are not restricted#{' '}
    to a narrow set of expressions like a "chatbot". However, since you are assisting the supervising teacher,#{' '}
    you should adhere to the requested curricula and refrain from expressing political opinions (with a broad definition#{' '}
    of 'politics', not just the civil kind). I'm sure you are wise enough to understand that the Overton window shifts over time,#{' '}
    sometimes quickly, and history is usually written by the victors--a student today may grow up to question or even resent what#{' '}
    he was taught, as new information becomes available. Even hard scientific fields like physics are fraught with philosophical#{' '}
    differences of opinion and fringe viewpoints. Therefore, be sure to cover topics broadly and be respectful of alternative viewpoints.#{' '}
    Our goal is not a student who can "enter the workforce" or be accepted by gatekeepers. We simply want to maximize the student's#{' '}
    potential by equipping him or her with knowledge, the ability to draw connections, be creative, utilize new and old tools#{' '}
    and technologies, utilize social resources and capital, exercise the natural need to be productive and accomplish useful work,#{' '}
    and appreciate the beauty of all these possibilities in our priviliged and undeserved position as humans.
  PROMPT
end

Prompt.find_or_create_by!(category: 'generate_course_outline') do |p|
  p.title = "Default Course Outline Generator"
  p.prompt = <<~PROMPT
    I am designing a course titled "{title}" for grade level {grade_level} with the following summary: "{summary}".#{' '}
    Please generate a detailed course outline in JSON format where each key is a topic (string) and each value is a brief description of that topic (string).#{' '}
    For example,#{' '}
    {#{' '}
      "Introduction to the Course": "Overview of course objectives and expectations",#{' '}
      "Chapter 1: Fundamentals": "Basic concepts and terminology",#{' '}
      ...#{' '}
    }#{' '}
    Don't nest beyond the key:value pairs.#{' '}
    Ensure the outline is comprehensive and suitable for the grade level.
  PROMPT
end

Prompt.find_or_create_by!(category: 'generate_lessons') do |p|
  p.title = "Default Lessons Generator"
  p.prompt = <<~PROMPT
    I am designing a course titled "{title}" for grade level {grade_level} with the following summary: "{summary}".
    The course has been outlined:
    {course_outline}
    The next step is to develop the list of lessons.
    Please generate a list of lessons for the course in JSON format using an array of hashes.
    For each lesson, include the title (string), goals (string), and suggested duration in minutes (integer).
    Lessons do not need to exactly correspond to outline topics one-to-one; for example, smaller topics could be grouped into a single lesson, or larger topics could be broken down into multiple lessons.
    If the outline appears to be incomplete, additional appropriate topics may be added within the lessons.
    Importantly, lesson length and depth should be appropriate for the grade level.#{' '}
    Don't ever exceed 60 minutes per lesson.#{' '}
    Provide enough detail in the goals so that a complete lesson plan could be inferred.#{' '}
    For example, for a course on 3D modeling:
    {[
      { "title": "Introduction to 3D Modeling",
        "goals": "Understand the basic concept of 3D modelling and its applications in various industries.
                  Familiarize students with the user interface of the chosen 3D modelling software.
                  Introduce the fundamental elements of 3D space: vertices, edges, and faces.
        "duration": 45 },
        ...
    ]}
    Don't nest beyond the key:value pairs.
    Ensure the outline is comprehensive and suitable for the grade level.
  PROMPT
end

puts "Seed data has been created successfully!"
