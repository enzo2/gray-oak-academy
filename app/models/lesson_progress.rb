class LessonProgress < ApplicationRecord
  # Represents a lesson in progress for a student

  belongs_to :student, class_name: "User"
  belongs_to :lesson
  has_one :teacher, through: :lesson
  has_one :conversation, dependent: :destroy
  has_one :student_report, as: :reportable, dependent: :nullify # Don't destroy student reports if the lesson/course is deleted.

  # Also includes JSONB fields for :chat_history and :progress_data; not currently needed since chat is in the Conversation and progress is in the StudentReport

  def find_or_create_conversation(user)
    conversation || create_conversation!(user)
  end

  def completed?
    student_report.present? && student_report.status_completed?
  end

  scope :completed, -> { joins(:student_report).where(student_reports: { status: :completed }) }

  def build_task_system_prompt
    base_prompt = Prompt.get_prompt(category: "lesson_tutor_session", user: teacher)
    # The lesson task system prompt is very important.
    # It contains all the information needed to conduct the lesson and evaluate the student.
    # In the future it can also include student profile information gathered from other courses, or the teacher.
    # We don't include student age for pedagogical reasons, since we want students to advance beyond their age level.
    lesson_info = <<~LESSON_INFO
      Course: #{lesson.course.title}
      Grade Level: #{lesson.course.grade_level}
      Lesson Title: #{lesson.title}
      Goals: #{lesson.goals}
      Duration: #{lesson.approx_duration_min} minutes (just a guide; could be shorter)
      Lesson Plan:
      #{lesson.lesson_plan.content}
      Resources marked as available:
      #{lesson.lesson_plan.resources.format_collection}
      Chalkboard enabled?: #{lesson.lesson_plan.chalkboard_enabled?}
      Student's name: #{student.name}
      Student's progress in previous lessons in this course:
      #{student.enrollments.find_by(course: lesson.course)&.lesson_history_for_prompt}
    LESSON_INFO
    base_prompt + "\n\n" + lesson_info
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
