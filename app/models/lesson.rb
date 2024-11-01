class Lesson < ApplicationRecord
  belongs_to :course
  acts_as_list scope: :course
  has_one :teacher, through: :course
  has_one :lesson_plan, dependent: :destroy
  has_many :student_reports, as: :reportable
  has_many :students, through: :course, inverse_of: :lessons
  has_many :lesson_progresses, dependent: :destroy

  validates :title, presence: true, length: { minimum: 3, maximum: 100 }
  validates :goals, presence: true, length: { minimum: 10, maximum: 1000 }
  validates :approx_duration_min, presence: true, numericality: { greater_than: 0, only_integer: true }

  scope :published, -> { joins(:lesson_plan).where(lesson_plans: { status: "published" }) }

  def completed_by?(student)
    student_reports.exists?(student: student, status: :completed)
  end

  # Returns the lessons that have not been completed by the given student, having no associated StudentReport
  # e.g. next_lesson = course.lessons.published.not_completed_by_student(student).first
  def self.not_completed_by_student(student)
    completed_lesson_ids = student.student_reports.status_completed.pluck(:lesson_id)
    where.not(id: completed_lesson_ids).order(:position)
  end

  def find_or_create_progress(student)
    LessonProgress.find_or_create_by(student: student, lesson: self)
  end

  def build_system_prompt
    base_prompt = Prompt.category_lesson_tutor_session.first.prompt
    lesson_info = <<~LESSON_INFO
      Course: #{course.title}
      Grade Level: #{course.grade_level}
      Lesson Title: #{title}
      Goals: #{goals}
      Duration: #{approx_duration_min} minutes
      Lesson Plan:
      #{lesson_plan.content}
      Resources marked as available:
      #{format_resources(lesson_plan.resources)}
    LESSON_INFO
    base_prompt + "\n\n" + lesson_info
  end

  def format_resources(resources)
    resources_data = resources.map do |resource|
      resource_info = {
        "Description" => resource.description
      }
      resource_info["Category"] = resource.category if resource.category.present?
      resource_info["URI"] = resource.uri if resource.uri.present?
      resource_info["file_attached"] = "Yes" if resource.file.attached?
      resource_info
    end
    JSON.pretty_generate(resources_data)
  end
end
