class LessonProgress < ApplicationRecord
  # Represents a lesson in progress for a student

  belongs_to :student, class_name: "User"
  belongs_to :lesson
  has_one :teacher, through: :lesson
  has_one :conversation, dependent: :destroy
  has_one :student_report, as: :reportable, dependent: :nullify # Don't destroy student reports if the lesson/course is deleted.

  # Enforce no duplicate progresses for the same student and lesson
  validates_uniqueness_of :student_id, scope: :lesson_id, message: "has already started progress on this lesson."

  # Also includes JSONB fields for :chat_history and :progress_data; not currently needed since chat is in the Conversation and progress is in the StudentReport

  def find_or_create_conversation(user)
    conversation || create_conversation!(user)
  end

  def completed?
    student_report.present? && student_report.status_completed?
  end

  scope :completed, -> { joins(:student_report).where(student_reports: { status: :completed }) }

  def course # For convenience
    lesson.course
  end

  def lesson_plan # For convenience
    lesson.lesson_plan
  end

  def resources # For convenience
    lesson_plan.resources
  end

  def build_task_system_prompt
    # The lesson task_system_prompt is very important.
    # It contains all the information needed to 1) conduct the lesson, 2) personalized to the student, and 3) evaluate the student at the end.
    # In the future it can also include student profile information gathered from other courses, or the teacher.
    # We don't include student age for pedagogical reasons, since we want students to advance beyond their age level.
    generative_guidelines = Prompt.get_prompt(category: "generative_guidelines", user: teacher)
    lesson_tutor_session_prompt = Prompt.get_prompt(category: "lesson_tutor_session", user: teacher)
    lesson_info = <<~LESSON_INFO
      Course: #{course.title}
      Grade Level: #{course.grade_level}
      Lesson Title: #{lesson.title}
      Estimated Duration: #{lesson.approx_duration_min} minutes (just a guide; could be shorter)
      Chalkboard enabled?: #{lesson_plan.chalkboard_enabled?}
      Audio setting: #{ (lesson_plan.audio == "audio-only" ? "Audio/Speech-only. Keyboard is disabled." : "Flexible: Student can type or use speech-to-text.") }
      Goals: #{lesson.goals}
      Lesson Plan:
      #{lesson_plan.content}

      Resources marked as available:
      #{resources.format_collection}

      Student's name: #{student.name}
      Student's progress in previous lessons in this course:
      #{student.enrollments.find_by(course: lesson.course)&.lesson_history_for_prompt}
      Memories about this student:
      #{Memory.for_prompt(user: student)}
    LESSON_INFO
    generative_guidelines + "\n\n" + lesson_tutor_session_prompt + "\n\n" + lesson_info
  end

  private

  def create_conversation!(user)
    conversation = Conversation.create!(
      user: user,
      lesson_progress: self,
      title: lesson.title,
      # This prompt will contain all the information needed to conduct the lesson and evaluate the student
      task_system_prompt: build_task_system_prompt
    )

    Message.create!(
      conversation: conversation,
      role: :assistant,
      content: "Ready to begin?"
    )

    conversation
  end
end
