class Image < ApplicationRecord
  # Images may be stored as URI or file.

  # fields:
  #   t.string :uri, null: true
  #   t.enum :content_type, enum_type: :content_type, null: false
  #   t.string :description, null: true

  belongs_to :message
  has_one_attached :file

  before_validation :set_content_type
  validate :image_present
  validates :content_type, presence: true

  # Convert attached image to base64
  def to_base64
    if file.attached?
      resized_image = file.variant(resize_to_limit: [ 512, 512 ]).processed # Downscale image before base64 conversion
      Base64.strict_encode64(resized_image.download)
    else
      Rails.logger.warn "No file attached to image #{id}"
      nil
    end
  end

  def base64_for_LLM
    return nil unless file.attached?
    "data:#{content_type};base64,#{to_base64}"
  end

  def image_for_LLM
    if uri.present?
      uri
    else
      base64_for_LLM
    end
  end

  private

  def set_content_type
    if file.attached?
      self.content_type = file.content_type
    end
  end

  def image_present
    unless file.attached? || uri.present?
      errors.add(:base, "Must have an attached file or URI")
    end
  end
end
