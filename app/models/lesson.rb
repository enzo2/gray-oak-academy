class Lesson < ApplicationRecord
  belongs_to :course
  acts_as_list scope: :course # t.integer "position"
  has_one :teacher, through: :course
  has_one :lesson_plan, dependent: :destroy
  has_many :students, through: :course, inverse_of: :lessons
  has_many :lesson_progresses, dependent: :destroy
  has_many :student_reports, through: :lesson_progresses# , source: :reportable, source_type: "StudentReport"  #?needed

  validates :title, presence: true, length: { minimum: 3, maximum: 100 }
  validates :goals, presence: true, length: { minimum: 10, maximum: 1000 }
  validates :approx_duration_min, presence: true, numericality: { greater_than: 0, only_integer: true }
  validate :quick_lesson_course_has_single_lesson

  scope :published, -> { joins(:lesson_plan).where(lesson_plans: { status: "published" }) }

  def started_by?(student)
    lesson_progresses.find_by(student: student).present?
  end

  # Check if the student has a completed StudentReport associated with this lesson
  def completed_by?(student)
    lesson_progress = lesson_progresses.find_by(student: student)
    return false if lesson_progress.nil?
    lesson_progress.completed?
  end

  # LessonProgress is created when the student starts the lesson
  def find_or_create_progress(student)
    LessonProgress.find_or_create_by(student: student, lesson: self)
  end

  # Returns an authorization status for student lesson access:
  # :ok, :not_enrolled, :ahead_of_progress, :wrong_teacher, :missing_lesson_plan, :unpublished_lesson
  def student_access_status_for(student)
    enrollment = student.enrollments.find_by(course_id: course_id)
    return :not_enrolled unless enrollment
    return :ahead_of_progress unless enrollment.not_ahead_of_progress?(position)
    return :wrong_teacher unless belongs_to_student_teacher_or_student?(student)
    return :missing_lesson_plan unless lesson_plan.present?
    return :unpublished_lesson unless lesson_plan.status_published?

    :ok
  end

  def student_access_allowed?(student)
    student_access_status_for(student) == :ok
  end

  def belongs_to_student_teacher_or_student?(student)
    owner_ids = [ student.teacher_id, student.id ].compact
    owner_ids.include?(course.teacher_id)
  end

  def for_llm
    lp = lesson_plan
    {
      lesson: {
        id: self.id,
        title: self.title,
        goals: self.goals,
        approx_duration_min: self.approx_duration_min,
        position: self.position,
        course_id: self.course_id
      },
      lesson_plan: (lp ? {
        id: lp.id,
        status: lp.status,
        generation_stage: lp.generation_stage,
        generation_error: lp.generation_error,
        content: lp.content,
        suggested_resources: lp.suggested_resources,
        linked_resources: lp.resources.format_collection(pretty: false),
        audio: lp.audio,
        chalkboard_enabled: lp.chalkboard_enabled
      } : nil)
    }
  end

  private

  def quick_lesson_course_has_single_lesson
    return unless course&.kind_quick_lesson?

    sibling_scope = course.lessons
    sibling_scope = sibling_scope.where.not(id: id) if persisted?
    return unless sibling_scope.exists?

    errors.add(:course, "quick lessons can only contain one lesson.")
  end
end
