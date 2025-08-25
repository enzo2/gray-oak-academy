class Resource < ApplicationRecord
  has_and_belongs_to_many :lesson_plans
  has_one_attached :file
  belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :resources, optional: true
  # If Teacher is deleted, we won't delete their resources

  validate :single_presence_of_file_or_uri

  # For a collection of Resources, format the data as JSON so it can be provided to the LLM
  def self.format_collection(pretty: true)
    resources_data = all.map do |resource|
      resource_info = {
        "Description" => resource.description
      }
      resource_info["Category"] = resource.category if resource.category.present?
      resource_info["URI"] = resource.uri if resource.uri.present?
      if resource.file.attached?
        resource_info["file_attached"] = "Yes"
        resource_info["resource_id"] = resource.id.to_s
        resource_info["filename"] = resource.file.filename.to_s
        resource_info["content_type"] = resource.file.content_type
      end
      resource_info
    end
    resources_data << { "No Resources" => "No resources are yet linked to this lesson." } if resources_data.empty?
    if pretty
      JSON.pretty_generate(resources_data)
    else
      resources_data.to_json
    end
  end

  private

  def single_presence_of_file_or_uri
    if file.attached? && uri.present?
      errors.add(:base, "File and URI cannot both be present.")
    end
  end
end
