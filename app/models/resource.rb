class Resource < ApplicationRecord
  has_and_belongs_to_many :lesson_plans
  has_one_attached :file
  belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :resources

  validate :single_presence_of_file_or_uri


  def self.format_collection
    resources_data = all.map do |resource|
      resource_info = {
        "Description" => resource.description
      }
      resource_info["Category"] = resource.category if resource.category.present?
      resource_info["URI"] = resource.uri if resource.uri.present?
      resource_info["file_attached"] = "Yes" if resource.file.attached? # Need to include an ID so LLM can access the file
      resource_info
    end
    JSON.pretty_generate(resources_data)
  end

  private

  def single_presence_of_file_or_uri
    if file.attached? && uri.present?
      errors.add(:base, "File and URI cannot both be present.")
    end
  end
end
