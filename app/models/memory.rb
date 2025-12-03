class Memory < ApplicationRecord
  belongs_to :student, class_name: "User", inverse_of: :memories
  belongs_to :author, class_name: "User", inverse_of: :authored_memories, optional: true
  belongs_to :student_report, optional: true

  # text :body, null: false
  encrypts :body, deterministic: true

  has_neighbors :embedding

  validates :body, presence: true, length: { maximum: 5000 }
  validate :author_validations

  after_save :update_embedding_if_needed

  # boolean :hidden_from_student, default: false, null: false
  scope :visible_to_students, -> { where(hidden_from_student: false) }
  scope :hidden, -> { where(hidden_from_student: true) }

  def self.for_prompt(user:)
    memories = user.memories.map { |memory| "#{memory.body} #{" [hidden from student]" if memory.hidden_from_student?}" }.join("\n")
    # Limit to 50,000 characters for now. Will need to use embeddings in the future.
    memories.truncate(50_000)
  end

  def teacher_authored?
    author&.role_teacher? || false
  end

  def student_authored?
    author == student
  end

  def update_embedding
    return unless body.present?
    vector = EmbeddingService.get(body)
    update_column(:embedding, vector) if vector.present?
  end

  private

  def update_embedding_if_needed
    update_embedding if saved_change_to_body?
  end

  def author_validations
    return if author.blank? # can be blank if LLM-authored or deleted user
    return if author == student # student can author own memories
    return if author.role_superuser? # superusers can author any memories
    # teacher can author student's memories if they are the student's teacher
    return if author.role_teacher? && student.teacher == author
    errors.add(:author, "must be the student or their teacher")
  end
end
