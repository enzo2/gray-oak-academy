class Observation < ApplicationRecord
  HALF_LIFE_DAYS = 90.0

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

  scope :for_context, lambda {
    as_of = Time.current
    quoted_as_of = connection.quote(as_of)

    decay_sql = <<~SQL.squish
      observations.relevance_weight * POWER(
        0.5,
        GREATEST(
          0,
          EXTRACT(EPOCH FROM (#{quoted_as_of} - COALESCE(observations.last_validated_at, observations.created_at)))
        ) / (#{HALF_LIFE_DAYS} * 86400.0)
      )
    SQL

    approved
      .select("observations.*, #{decay_sql} AS effective_weight")
      .order(Arel.sql("effective_weight DESC"))
  }

  def effective_weight
    return self[:effective_weight].to_f if has_attribute?("effective_weight") && !self[:effective_weight].nil?

    anchor = last_validated_at || created_at
    return relevance_weight.to_f unless anchor

    days_stale = [ (Time.current - anchor) / 1.day, 0.0 ].max
    relevance_weight.to_f * (0.5 ** (days_stale / HALF_LIFE_DAYS))
  end

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
