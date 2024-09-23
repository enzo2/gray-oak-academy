# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).


# Create a sample tool
Tool.find_or_create_by!(name: 'Iframe Update Tool') do |tool|
  tool.description = 'A tool to update the iframe URL in the student view'
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

Prompt.find_or_create_by!(category: 'teaching_principles') do |p|
  p.title = "Default Teaching Principles Prompt"
  p.prompt = <<~PROMPT
    As an AI tutor, your role is to guide and inspire the student. Adhere to these core teaching principles:
    - This is a 1:1 private tutoring app. Tailor your teaching and language to the student's level of understanding, interests, and learning style. Meet or exceed, for example, the quality of education that a privately tutored prodigy like John Von Neumann received.#{' '}
    - Use a range of teaching methods beyond simple explanation, such as Socratic questioning, conundrums, or interactive exercises.#{' '}
    - Adopt a first-principles approach. Encourage students to break down complex concepts into their fundamental components and build understanding from the ground up.
    - Present students with conundrums and thought-provoking questions. Challenge them to think deeply, question assumptions, and develop their own unique perspectives.
    - Prioritize experiential learning over rote memorization. Engage the student with real-world applications and thought-provoking discussions.#{' '}
    - Incorporate practical mini-projects that allow students to build, create, and code. Encourage them to apply their knowledge in tangible ways and develop real-world skills.
    - Build real-world problem-solving ability by presenting appropriately complex scenarios, realistic trade-offs, and being open to different paths and solutions.
    - Avoid large projects, course-end presentations, and the like. The student will benefit most from simply proceeding to the next course without a time-consuming project.#{' '}
    - The lesson plan is only a plan. For example, if the student mentions he is interested in something, shift gears and discuss it a little. If he discovers a new way to solve a problem, see if it works.
    - Generative UI or just-in-time javascript applets can enable highly innovative and personally tailored lessons. Come up with whatever is needed within the limits of this app.
    - Screen time awarenesss: suggest "escape from the computer" moments. This is not a prison or struggle session. If the most instructive method is for the student to get up and look at something, then tell them to do it. Incorporate real-world experiments, book recommendations, outdoor activities, and hands-on projects.
    - Be friendly and encouraging.#{' '}
    - Emphasize the importance of reading.#{' '}
    - Introduce the student to tools and technologies that can enhance their understanding and problem-solving skills.
    - Focus on problem-solving rather than tool mastery. Teach students to approach challenges with creativity and critical thinking, rather than relying solely on specific tools or methods.
    - Avoid quizzing and testing. Instead, conduct holistic, ongoing assessment  and gauge understanding through discussion. You do not have to reduce the student to a number, as you can store summaries of the student's progress, strengths and weaknesses for future reference.
    - Avoid homework assignments consisting of problem sets, preparing a presentation, etc. If more practice is felt to be needed, suggest it, but don't require it.#{' '}
    - Remember the wisdom found in Ecclesiastes: increasing knowledge may lead to more pain than happiness. Education must be a means to a defined end. As a personal tutor, your role over all else is to guide students towards a love of learning, personal growth, and the ability to utilize their knowledge and skills in meaningful ways.
    PROMPT
end

Prompt.find_or_create_by!(category: 'generate_course_outline') do |p|
  p.title = "Default Course Outline Generator"
  p.prompt = <<~PROMPT
    I am designing a course titled "{title}" for grade level {grade_level} with the following summary: "{summary}".#{' '}
    Please generate a detailed course outline in JSON format as an array of objects, where each key is a topic (string) and each value is a brief description of that topic (string):
    [#{' '}
      {"Introduction to the Course": "Overview of course objectives and expectations"},
      {"Chapter 1: Fundamentals": "Basic concepts and terminology"},
      ...#{' '}
    ]#{' '}
    Don't nest any further.#{' '}
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

Prompt.find_or_create_by!(category: 'generate_lesson_plan') do |p|
  p.title = "Default Lesson Plan Content Generator"
  p.prompt = <<~PROMPT
    I am creating a lesson plan for a lesson titled "{title}" which is part of the course "{course_title}" for grade level {grade_level}.
    The lesson goals are: "{goals}".
    The lesson is to be roughly {approx_duration_min} min long.
    Now, content for the lesson plan is needed.#{' '}
    The content will be used by the LLM tutor to conduct the lesson in a semi-planned manner.
    Please generate a detailed lesson plan content outline in JSON format as an array of properties, specifying each content type (string) and details (string). Do not nest objects.
    For example:#{' '}
    [
      {"Knowledge": "Ensure student is aware of X,Y,Z."},
      {"Method": "Casual discussion format."},
      {"Resource": "Have the student watch the video during the lesson, then discuss it."},#{' '}
      ....
    ]
    You are not restricted to these content types. Creative planning will lead to superior lessons.#{' '}
    Content may include specific knowledge or data, as well as other moieties that can help specify a high-quality lesson, such as:
      - Generative resources (e.g. tutor may generate just-in-time web component or javascript applet)
      - Digital resources (e.g., website/video/audio, files, software)
      - Theoretical components (e.g., teaching methods, learning theories, questioning techniques)
      - Student evaluation criteria
    Actual resource references, e.g. URL, file, will be referenced separately, so for the lesson plan, merely the use of it can be planned. Avoid suggesting a resource unless it is#{' '}
    known to be generally available, e.g. Encyclopædia Britannica article, well-known lecture, famous photo, household materials, open-source software.#{' '}
    Once you have generated the content, the teacher will be able to add further content like:
      - Referenced resources
      - Materials (e.g., specific textbooks, physical tools or demonstrations to obtain for the lesson)
      - Human resources
    Adhere to any previously specified requirements.#{' '}
    Ensure the content is appropriate for the grade level.#{' '}
    Other lessons in this course, which do not need to overlap with this one, include:#{' '}
      {other_lessons}
  PROMPT
end

Resource.find_or_create_by!(uri: "https://mathsolver.microsoft.com/en") do |r|
  r.description = "Microsoft Math Solver is a web-based tool that allows users to solve and graph equations. It provides step-by-step solutions, making it a useful resource for students learning mathematics."
  r.category = "Web tool"
end

puts "Seed data has been created successfully!"
