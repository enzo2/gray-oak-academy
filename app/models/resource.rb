class Resource < ApplicationRecord
  has_and_belongs_to_many :lesson_plans
  has_one_attached :file
  belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :resources

  validate :single_presence_of_file_or_uri

  private

  def single_presence_of_file_or_uri
    if file.attached? && uri.present?
      errors.add(:base, "File and URI cannot both be present.")
    end
  end
end
