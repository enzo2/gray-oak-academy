class LessonPlan < ApplicationRecord
  belongs_to :lesson
  belongs_to :teacher, class_name: "User", inverse_of: :lesson_plans
  has_one :course, through: :lesson
  has_and_belongs_to_many :resources

  # Field: t.jsonb :content, default: [] # Array of hashes [{type:details}, ....]
  # Field: t.boolean :chalkboard_enabled, default: true

  enum :status, { draft: "draft", published: "published" }, prefix: true
  # "archived" status also available in the enum column, but can't think of a use case

  enum :audio, { disabled: "disabled", enabled: "enabled", audio_only: "audio-only" }, prefix: true

  # Allow blank content if still new draft
  validate :validate_content_format, unless: -> { status == "draft" && content.blank? }

  private

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
