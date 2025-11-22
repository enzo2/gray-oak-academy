class Observation < ApplicationRecord
  belongs_to :student, class_name: "User"
  belongs_to :author, class_name: "User", optional: true
  belongs_to :source, polymorphic: true, optional: true

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected", archived: "archived" }, prefix: true

  has_neighbors :embedding

  validates :content, presence: true
  validates :status, presence: true
  validates :relevance_weight, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }

  scope :pending, -> { where(status: :pending) }
  scope :approved, -> { where(status: :approved) }
  scope :rejected, -> { where(status: :rejected) }
  scope :archived, -> { where(status: :archived) }

  # For the LLM context, we typically want approved observations,
  # possibly weighted by relevance in the future.
  scope :for_context, -> { approved.order(created_at: :desc) }

  def embedding_text
    content
  end

  # Automatically generate embedding if configured (similar to Memory)
  after_save :update_embedding_if_needed

  def update_embedding
    return unless content.present?
    return unless AppSetting.embeddings_configured?

    vector = EmbeddingService.get(content)
    update_column(:embedding, vector) if vector.present?
  end

  private

  def update_embedding_if_needed
    update_embedding if saved_change_to_content?
  end
end
