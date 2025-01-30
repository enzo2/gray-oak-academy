class LessonPlan < ApplicationRecord
  # Field: t.jsonb :content, default: [] # Array of hashes [{type:details}, ....]

  belongs_to :lesson
  belongs_to :teacher, class_name: "User", inverse_of: :lesson_plans
  has_one :course, through: :lesson
  has_and_belongs_to_many :resources

  enum :status, { draft: "draft", published: "published", archived: "archived" }, prefix: true

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
