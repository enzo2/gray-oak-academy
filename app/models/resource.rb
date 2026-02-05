class Resource < ApplicationRecord
  has_and_belongs_to_many :lesson_plans
  has_one_attached :file
  has_one :applet, dependent: :destroy, validate: true
  accepts_nested_attributes_for :applet, allow_destroy: true, reject_if: :all_blank

  belongs_to :teacher, class_name: "User", foreign_key: "teacher_id", inverse_of: :resources, optional: true
  # If Teacher is deleted, we won't delete their resources, since they may be useful to other teachers
  # todo: orphaned resources reassignment / view app-wide resources

  # If description is blank, provide a default depending on the payload type
  before_validation do
    if description.blank?
      if file.attached?
        self.description = "File: #{file.filename}"
      elsif uri.present?
        self.description = "Link: #{uri}"
      elsif applet.present? && !applet.marked_for_destruction?
        self.description = "Applet: #{applet.title}"
      end
    end
  end

  # Ensure nested applet created/updated through Resource gets a user assigned.
  before_validation :assign_applet_user, if: -> { applet.present? && !applet.marked_for_destruction? }

  validate :single_presence_of_payload

  def self.normalize_tags(value)
    raw_tags = case value
    when String
      value.split(",")
    when Array
      value.flat_map { |tag| tag.to_s.split(",") }
    when nil
      []
    else
      Array(value)
    end

    raw_tags.map { |tag| tag.to_s.strip.downcase }.reject(&:blank?).uniq
  end

  def self.normalize_category(value)
    return if value.nil?

    normalized = value.to_s.strip
    return if normalized.blank?

    normalized[0] = normalized[0].upcase
    normalized
  end

  def self.distinct_tags_for(teacher)
    normalize_tags(where(teacher: teacher).pluck(:tags).flatten.compact).sort
  end

  def self.most_used_tags_for(teacher, limit: 20)
    tags = where(teacher: teacher).pluck(:tags).flatten.compact
    counts = tags.each_with_object(Hash.new(0)) { |tag, memo| memo[tag] += 1 }
    counts.sort_by { |tag, count| [ -count, tag ] }.first(limit).map(&:first)
  end

  def self.distinct_categories_for(teacher)
    where(teacher: teacher).where.not(category: [ nil, "" ]).distinct.order(:category).pluck(:category)
  end

  def tags=(value)
    super(self.class.normalize_tags(value))
  end

  def category=(value)
    super(self.class.normalize_category(value))
  end

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
      if resource.applet.present?
        resource_info["applet_title"] = resource.applet.title
        resource_info["applet_id"] = resource.applet.id
        resource_info["applet_reminder_msg"] = "Code not included for brevity. Do not invent your own code! To retrieve, use the View_Applets tool with action: get and applet_id: #{resource.applet.id}"
        # resource_info["applet_code"] = resource.applet.code  # Including the full code within JSON causes syntax errors when LLM forgets to remove escaping.
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

  def assign_applet_user
    return unless applet.present? && !applet.marked_for_destruction?
    # Prefer the resource's teacher (set in controller) but do not override an existing user.
    applet.user ||= teacher
  end

  def single_presence_of_payload
    payloads = [
      file.attached?,
      uri.present?,
      applet.present? && !applet.marked_for_destruction?
    ].count(true)
    if payloads > 1
      errors.add(:base, "Only one payload variety (File, URI, or Applet) can be present.")
    end
  end
end
