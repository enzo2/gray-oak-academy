class LessonProgress < ApplicationRecord
  # includes JSONB fields for :chat_history and :progress_data; should not be needed since chat is in the Conversation and progress is in the StudentReport

  belongs_to :student, class_name: "User"
  belongs_to :lesson
  has_one :teacher, through: :lesson
  has_one :conversation, dependent: :destroy
  has_one :student_report, as: :reportable, dependent: :destroy

  def find_or_create_conversation(user)
    conversation || create_conversation!(user)
  end

  def completed?
    student_report.present? && student_report.status_completed?
  end

  scope :completed, -> { joins(:student_report).where(student_reports: { status: :completed }) }

  def build_task_system_prompt
    base_prompt = Prompt.category_lesson_tutor_session.first.prompt
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
      Student's name: #{student.name}
      Student's progress in previous lessons in this course:
      #{previous_lesson_reports}
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
      content: "Hello. Ready to begin?"
    )

    conversation
  end

  def previous_lesson_reports
    student = self.student
    course = self.lesson.course
    enrollment = student.enrollments.find_by(course: course)

    completed_lessons_in_course = enrollment.completed_lessons

    if completed_lessons_in_course.empty?
      "No previous lessons completed in this course yet."
    else
      completed_lessons_in_course.map do |lesson|
        # Find the student report
        report = lesson.student_reports.where(student: student).first
        report_content = report.progress_data.to_s || "Report details not available."
        "Lesson: #{lesson.title}, Report: #{report_content}"
      end.join("\n")
    end
  end
end
