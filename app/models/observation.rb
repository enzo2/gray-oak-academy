class Observation < ApplicationRecord
  HALF_LIFE_DAYS = 90.0
  MANAGEMENT_SORT_DEFAULT = "chron_desc".freeze
  MANAGEMENT_SORT_OPTIONS = [
    [ "Chronological (newest first)", "chron_desc" ],
    [ "Chronological (oldest first)", "chron_asc" ],
    [ "Weight (high to low)", "weight_desc" ],
    [ "Weight (low to high)", "weight_asc" ]
  ].freeze
  MANAGEMENT_SORT_KEYS = MANAGEMENT_SORT_OPTIONS.map(&:last).freeze

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
    with_effective_weight(approved, as_of: Time.current)
      .order(Arel.sql("effective_weight DESC"))
  }

  def self.management_sort_options
    MANAGEMENT_SORT_OPTIONS
  end

  def self.normalize_management_sort(value)
    value.to_s.presence_in(MANAGEMENT_SORT_KEYS) || MANAGEMENT_SORT_DEFAULT
  end

  def self.for_management_timeline(student:, sort:, as_of: Time.current)
    normalized_sort = normalize_management_sort(sort)
    relation = with_effective_weight(where(student: student).includes(:author), as_of: as_of)
    apply_management_sort(relation, normalized_sort)
  end

  def self.effective_weight_sql(as_of:, table_name: "observations")
    quoted_as_of = connection.quote(as_of)

    <<~SQL.squish
      #{table_name}.relevance_weight * POWER(
        0.5,
        GREATEST(
          0,
          EXTRACT(EPOCH FROM (#{quoted_as_of} - COALESCE(#{table_name}.last_validated_at, #{table_name}.created_at)))
        ) / (#{HALF_LIFE_DAYS} * 86400.0)
      )
    SQL
  end

  def self.with_effective_weight(relation = all, as_of: Time.current)
    decay_sql = effective_weight_sql(as_of: as_of)
    relation.select("#{table_name}.*, #{decay_sql} AS effective_weight")
  end

  def self.apply_management_sort(relation, sort)
    case sort
    when "chron_asc"
      relation.order(created_at: :asc)
    when "weight_desc"
      relation.order(Arel.sql("effective_weight DESC, observations.created_at DESC"))
    when "weight_asc"
      relation.order(Arel.sql("effective_weight ASC, observations.created_at DESC"))
    else
      relation.order(created_at: :desc)
    end
  end

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
