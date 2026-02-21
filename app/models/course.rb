class Course < ApplicationRecord
  OUTLINE_GUIDANCE_ADDITIONAL_COMMENTS_KEY = "_additional_comments".freeze
  OUTLINE_RESEARCH_STAGES = %w[
    idle
    researching_outline
    generating_guidance_questions
    awaiting_teacher_input
    applying_guidance_updates
    completed
    failed
  ].freeze

  belongs_to :teacher, class_name: "User", inverse_of: :taught_courses
  has_many :students, through: :enrollments, inverse_of: :courses
  has_many :lessons, -> { order(position: :asc) }, dependent: :destroy
  has_many :lesson_plans, through: :lessons
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
  validates :outline_research_stage, inclusion: { in: OUTLINE_RESEARCH_STAGES }
  validate :validate_outline_format
  validate :validate_outline_guidance_questions_limit
  before_validation :normalize_outline_guidance_report_md_line_breaks

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
      outline_research_stage: self.outline_research_stage,
      outline_research_error: self.outline_research_error,
      outline_research: self.outline_research,
      outline_guidance_report_md: self.outline_guidance_report_md,
      outline_guidance_questions: self.outline_guidance_questions,
      outline_guidance_answers: self.outline_guidance_answers,
      outline_guidance_additional_comments: outline_guidance_additional_comments,
      unanswered_research_question_ids: unanswered_research_question_ids,
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

  def outline_research_hash
    outline_research.is_a?(Hash) ? outline_research : {}
  end

  def outline_guidance_answers_hash
    outline_guidance_answers.is_a?(Hash) ? outline_guidance_answers : {}
  end

  def outline_guidance_additional_comments
    outline_guidance_answers_hash[OUTLINE_GUIDANCE_ADDITIONAL_COMMENTS_KEY].to_s
  end

  def outline_research_in_progress?
    %w[researching_outline generating_guidance_questions applying_guidance_updates].include?(outline_research_stage)
  end

  def awaiting_outline_research_input?
    outline_research_stage == "awaiting_teacher_input"
  end

  def outline_research_input_open?
    awaiting_outline_research_input? || outline_research_stage == "failed"
  end

  def outline_guidance_report_present?
    outline_guidance_report_md.to_s.strip.present?
  end

  def outline_research_review_page_available?
    outline_research_input_open? || outline_guidance_report_present?
  end

  def outline_research_resumable_run?
    outline_research_response_id.to_s.present?
  end

  def outline_research_restart_blocked?
    return true if awaiting_outline_research_input?
    return false unless outline_research_stage == "failed"

    outline_research_resumable_run?
  end

  def unanswered_research_question_ids
    answers = outline_guidance_answers_hash
    Array(outline_guidance_questions).filter_map do |question|
      next unless question.is_a?(Hash)

      id = question["id"].to_s
      next if id.blank?
      next if outline_guidance_answer_complete?(answers[id])

      id
    end
  end

  def reset_outline_research!
    with_lock do
      reload
      update!(
        outline_research_stage: "idle",
        outline_research_error: nil,
        outline_research: {},
        outline_guidance_report_md: nil,
        outline_guidance_questions: [],
        outline_guidance_answers: {},
        outline_research_run_id: nil,
        outline_research_response_id: nil,
        course_prior_state: {}
      )
    end
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

  def validate_outline_guidance_questions_limit
    questions = Array(outline_guidance_questions)
    return if questions.size <= 5

    errors.add(:outline_guidance_questions, "must contain at most 5 questions.")
  end

  def outline_guidance_answer_complete?(raw_answer)
    payload = parse_outline_guidance_answer(raw_answer)
    choice = payload["choice"].to_s.upcase

    return true if %w[A B C].include?(choice)
    return payload["other_text"].to_s.strip.present? if choice == "OTHER"

    false
  end

  def parse_outline_guidance_answer(raw_answer)
    case raw_answer
    when Hash
      raw_answer.deep_stringify_keys
    when String
      raw = raw_answer.to_s
      return {} if raw.blank?

      payload = JSON.parse(raw)
      payload.is_a?(Hash) ? payload : {}
    else
      {}
    end
  rescue JSON::ParserError
    {}
  end

  def normalize_outline_guidance_report_md_line_breaks
    report = outline_guidance_report_md
    return unless report.is_a?(String)
    return if report.include?("\n")

    escaped_newline_count = report.scan(/\\n/).size
    return if escaped_newline_count < 2

    self.outline_guidance_report_md = report.gsub("\\r\\n", "\n").gsub("\\n", "\n")
  end
end
