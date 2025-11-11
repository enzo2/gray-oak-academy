class Memory < ApplicationRecord
  belongs_to :student, class_name: "User", inverse_of: :memories
  belongs_to :author, class_name: "User", inverse_of: :authored_memories, optional: true
  belongs_to :student_report, optional: true

  # text :body, null: false
  encrypts :body, deterministic: true

  validates :body, presence: true, length: { maximum: 5000 }
  validate :author_validations

  # boolean :hidden_from_student, default: false, null: false
  scope :visible_to_students, -> { where(hidden_from_student: false) }
  scope :hidden, -> { where(hidden_from_student: true) }

  def teacher_authored?
    author&.role_teacher? || false
  end

  def student_authored?
    author == student
  end

  private

  def author_validations
    return if author.blank? # can be blank if LLM-authored or deleted user
    return if author == student # student can author own memories
    return if author.role_superuser? # /superusers can author any memories
    # teacher can author student's memories if they are the student's teacher
    return if author.role_teacher? && student.teacher == author
    errors.add(:author, "must be the student or their teacher")
  end
end
