class LessonPlan < ApplicationRecord
  belongs_to :lesson
  belongs_to :teacher, class_name: "User", inverse_of: :lesson_plans
  has_one :course, through: :lesson
  has_and_belongs_to_many :resources

  validates_uniqueness_of :lesson_id # lesson has_one lesson_plan

  # Field: t.jsonb :content, default: [] # Array of hashes [{type => details}, ...]
  # Field: t.jsonb :suggested_resources, default: [] # Array of hashes [{type => description}, ...]
  # Field: t.boolean :chalkboard_enabled, default: true, null: false
  # Field: t.enum :audio, enum_type: :audio_setting, default: "enabled", null: false

  enum :status, { draft: "draft", published: "published" }, prefix: true
  # "archived" status also available in the enum column, but can't think of a use case

  # Setting for audio input: see conversation.rb for definitions
  enum :audio, { enabled: "enabled", only: "audio-only" }, prefix: true
  # "disabled" status also available in the enum column, but confusing since STT is always enabled

  # Allow blank content if still new draft
  validate :validate_content_format, unless: -> { status == "draft" && content.blank? }

  after_initialize :link_default_resources, if: :new_record?

  private

  def link_default_resources
    default_resources = Resource.where(include_by_default: true)
    resources << default_resources
  end

  def validate_content_format
    if content.empty?
      errors.add(:content, "must be added.")
    else
      content.each do |item|
        if item.keys.first.blank? || item.values.first.blank?
          errors.add(:content, "entries must have both a type and details.")
        end
      end
    end
  end
end
