class Prompt < ApplicationRecord
  belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :prompts, optional: true

  enum :category, {
    other: "other",
    generate_course_outline: "generate_course_outline",
    generate_lessons: "generate_lessons",
    generate_lesson_plan: "generate_lesson_plan",
    suggest_resources: "suggest_resources",
    lesson_tutor_session: "lesson_tutor_session",
    open_ended_student_chat: "open_ended_student_chat",
    student_progress_tutor_session: "student_progress_tutor_session",
    generate_student_lesson_report: "generate_student_lesson_report",
    generate_student_assessment_report: "generate_student_assessment_report",
    generate_student_profile: "generate_student_profile",
    tool_usage: "tool_usage",
    teacher_assistant: "teacher_assistant",
    teaching_principles: "teaching_principles",
    base_system_prompt: "base_system_prompt"
  }, validate: true, prefix: true

  FRIENDLY_CATEGORIES = {
    other: "Other",
    generate_course_outline: "Generate Course Outline",
    generate_lessons: "Generate Lessons",
    generate_lesson_plan: "Generate Lesson Plan",
    suggest_resources: "Suggest Resources",
    lesson_tutor_session: "Lesson Tutor Session", # for conducting the lesson plan with student
    open_ended_student_chat: "Open-Ended Student Chat", # for student 1:1 chat outside of lessons
    student_progress_tutor_session: "Student Progress Tutor Session", # for providing the student with constructive feedback
    generate_student_lesson_report: "Generate Student Lesson Report", # post-lesson assessment
    generate_student_assessment_report: "Generate Student Assessment Report", # post-course assessment
    generate_student_profile: "Generate Student Profile", # for processing RAG results before a lesson
    tool_usage: "Tool Usage", # for enabling LLM to control the app during a lesson, generate UI, etc.
    teacher_assistant: "Teacher Assistant", # for 1:1 teacher assistant chat
    teaching_principles: "Teaching Principles", # appended to the base system prompt to establish teaching principles, ethical boundaries, etc.
    base_system_prompt: "Base System Prompt" # prepended to all prompts to explain the app
  }

  validates :title, presence: true
  validates :category, presence: true, uniqueness: { scope: :teacher_id } # Ensures uniqueness of category per teacher
  validates :prompt, presence: true

  # Scopes
  scope :by_category, ->(category:) { where(category: category) }
  scope :system_prompts, -> { where(category: [ :base_system_prompt, :teaching_principles ]) }
  scope :lesson_related, -> { where(category: [ :generate_lessons, :generate_lesson_plan, :lesson_tutor_session ]) }

  # Helper method to get user-friendly category name
  def friendly_category_name
    FRIENDLY_CATEGORIES[category.to_sym]
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
