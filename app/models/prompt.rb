class Prompt < ApplicationRecord
  belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :prompts, optional: true

  # Don't hard-code any prompts (whether system or user messages). All prompts should use this model and have a default in seeds.db.

  enum :category, {
    other: "other", # unused
    generate_course_outline: "generate_course_outline", # self-explanatory
    generate_lessons: "generate_lessons", # self-explanatory
    generate_lesson_plan: "generate_lesson_plan", # self-explanatory
    suggest_resources: "suggest_resources", # propose/validate lesson resources
    lesson_tutor_session: "lesson_tutor_session", # for conducting the lesson plan with student
    open_ended_student_chat: "open_ended_student_chat", # for student 1:1 chat outside of lessons
    auto_name_conversation: "auto_name_conversation", # auto-generate short chat titles
    # student_progress_tutor_session: "student_progress_tutor_session", # Unused, can be for a planning session, 'office hours', student-directed lesson planning, etc.
    # generate_student_lesson_report: "generate_student_lesson_report", # Unused; specified in a Tool
    generate_student_course_report: "generate_student_course_report", # Generate the course-end report
    # generate_student_assessment_report: "generate_student_assessment_report", # unused, could be for reports outside of a course/lesson, eg. one-off tutoring session, remedial/review, vibe check, etc.
    generate_student_profile: "generate_student_profile", # Periodic synthesized profile of student progress
    generative_guidelines: "generative_guidelines",  # LLM instructions for generative UI/UX and code execution
    teacher_assistant: "teacher_assistant", # for 1:1 teacher assistant chat
    teaching_principles: "teaching_principles", # appended to the base system prompt to establish teaching style, principles, ethical boundaries, etc.
    base_system_prompt: "base_system_prompt", # prepended to all prompts to explain foundational principles
    # tool_usage: "tool_usage", # unused, there is a Tool model for this
    delegate_to_frontier_llm: "delegate_to_frontier_llm", # allow model to query the thinking LLM
    memories_semantic_merge: "memories_semantic_merge", # merge new student memories via LLM
    generate_observations: "generate_observations", # generate academic observations from lesson reports
    research_course_outline: "research_course_outline", # Exa-grounded course-level research retrieval
    analyze_course_outline_research: "analyze_course_outline_research", # synthesize report + teacher questions
    apply_course_outline_research: "apply_course_outline_research" # interpret teacher input and apply updates
  }, validate: true, prefix: true

  FRIENDLY_CATEGORIES = {
    other: "Other",
    generate_course_outline: "Generate Course Outline",
    generate_lessons: "Generate Lessons",
    generate_lesson_plan: "Generate Lesson Plan",
    suggest_resources: "Suggest Resources",
    lesson_tutor_session: "Lesson Tutor Session",
    open_ended_student_chat: "Open-Ended Student Chat",
    auto_name_conversation: "Auto-Name Conversation",
    # student_progress_tutor_session: "Student Progress Tutor Session",
    # generate_student_lesson_report: "Generate Student Lesson Report",
    generate_student_course_report: "Generate Student Course Report",
    # generate_student_assessment_report: "Generate Student Assessment Report",
    generate_student_profile: "Generate Student Profile",
    generative_guidelines: "Generative Guidelines",
    teacher_assistant: "Teacher Assistant",
    teaching_principles: "Teaching Principles",
    base_system_prompt: "Base System Prompt",
    # tool_usage: "Tool Usage",
    delegate_to_frontier_llm: "Delegate To Frontier LLM",
    memories_semantic_merge: "Memories: Semantic Merge",
    generate_observations: "Generate Observations",
    research_course_outline: "Research Course Outline",
    analyze_course_outline_research: "Analyze Course Outline Research",
    apply_course_outline_research: "Apply Course Outline Research"
  }

  validates :title, presence: true
  validates :category, presence: true, uniqueness: { scope: :teacher_id } # Ensures uniqueness of category per teacher
  validates :prompt, presence: true

  # Scopes
  scope :by_category, ->(category:) { where(category: category) }
  scope :system_prompts, -> { where(category: [ :base_system_prompt, :teaching_principles ]) }
  scope :lesson_related, -> { where(category: [ :generate_lessons, :generate_lesson_plan, :lesson_tutor_session ]) }

  # Get the teacher-modified prompt; if none, use the default prompt
  def self.get_prompt(category:, user: nil)
    if user&.role_teacher?
      prompt = Prompt.find_by(category: category, teacher_id: user.id)
    elsif user&.role_student?
      teacher = user.teacher
      prompt = Prompt.find_by(category: category, teacher_id: teacher.id) if teacher
    end
    prompt ||= Prompt.find_by(category: category, teacher_id: nil)
    if prompt&.prompt.present?
      prompt.prompt
    else
      raise "Prompt '#{category}' is missing. Run `bin/rails db:seed` or create it in Admin > Prompts."
    end
  end

  # Helper method to get user-friendly category name
  def friendly_category_name
    FRIENDLY_CATEGORIES[category.to_sym]
  end

  # The "full system prompt" is the base system prompt + teaching principles.
  # Any specific task should provide a task_system_prompt to OpenaiApiService, which will be appended to the full_system_prompt.
  # (Don't forget to include the generative_guidelines in task_system_prompt if warranted.)
  # Thus, the final concatenated system prompt would be base_system_prompt + teaching_principles + task_system_prompt
  # To completely override all of this, include a system message in the messages array.
  def self.full_system_prompt(user:)
    Prompt.get_prompt(category: "base_system_prompt", user: user) + "\n\n" + Prompt.get_prompt(category: "teaching_principles", user: user) + "\n\n"
  end

  # Class method to get all categories with their friendly names
  def self.category_options
    categories.map { |category, _value| [  category, FRIENDLY_CATEGORIES[category.to_sym] ] }
  end

  # If you need to check if a friendly name is valid
  def self.valid_friendly_category?(friendly_name)
    FRIENDLY_CATEGORIES.value?(friendly_name)
  end
end
