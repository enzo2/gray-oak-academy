class Course < ApplicationRecord
  belongs_to :teacher, class_name: "User", inverse_of: :taught_courses
  has_many :students, through: :enrollments, inverse_of: :courses
  has_many :lessons, -> { order(position: :asc) }, dependent: :destroy
  has_many :enrollments
  has_many :student_reports, through: :enrollments

  enum :status, { active: "active", archived: "archived" }, default: "active", prefix: true
  # scope :active, -> { where(status: "active") }
  # scope :archived, -> { where(status: "archived") }

  validates :title, presence: true, length: { minimum: 3, maximum: 100 }
  validates :summary, presence: true, length: { minimum: 10, maximum: 2000 }
  validates :grade_level,
            presence: true,
            format: {
              with: /\A([A-Z]|[1-9]\d*)\z/,
              message: "must be a single uppercase letter or a positive integer."
            }
    validate :validate_outline_format

  def enrolled_in?(student)
    enrollments.exists?(student: student)
  end

  def completed_by?(student)
    enrollments.exists?(student: student, completed: true)
  end

  def self.available_for_enrollment(student, teacher)
    # status_active.where(teacher: teacher).reject { |course| course.enrolled_in?(student) }
    status_active
      .where(teacher: teacher)
      .where.not(id: student.courses.select(:id))
  end

  def for_llm
    {
      id: self.id,
      title: self.title,
      summary: self.summary,
      grade_level: self.grade_level,
      status: self.status,
      outline: self.outline,
      lessons: self.lessons.map do |l|
        {
          id: l.id,
          title: l.title,
          goals: l.goals,
          approx_duration_min: l.approx_duration_min,
          position: l.position,
          plan_status: l.lesson_plan&.status
        }
      end
    }
  end

  private

  def validate_outline_format
    if outline.present?
      outline.each do |item|
        if item.keys.first.blank? || item.values.first.blank?
          errors.add(:outline, "entries must have both a topic and details.")
        end
      end
    end
  end
end
