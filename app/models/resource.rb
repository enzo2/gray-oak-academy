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
      elsif content.present?
        self.description = "Text resource"
      elsif applet.present? && !applet.marked_for_destruction?
        self.description = "Applet: #{applet.title}"
      end
    end
  end

  # Ensure nested applet created/updated through Resource gets a user assigned.
  before_validation :assign_applet_user, if: -> { applet.present? && !applet.marked_for_destruction? }
  before_validation :normalize_youtube_uri

  validate :single_presence_of_payload
  validate :youtube_uri_must_be_embed

  scope :available_for_tutor, -> { where(approved: [ nil, true ]) }
  scope :pending_approval, -> { where(approved: false) }

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
    resources = includes(:applet, file_attachment: :blob).to_a
    resources_data = resources.map do |resource|
      resource_info = {
        "Description" => resource.description
      }
      resource_info["Category"] = resource.category if resource.category.present?
      resource_info["Approval"] = case resource.approved
      when true
        "LLM-created and approved"
      when false
        "LLM-created and pending approval"
      else
        "Human-created"
      end
      resource_info["URI"] = resource.uri if resource.uri.present?
      resource_info["Content"] = resource.content if resource.content.present?
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

  # For human-clicked links in the admin UI, convert YouTube embed URLs back to
  # watch URLs so they open reliably outside iframes.
  def uri_for_direct_visit
    return uri if uri.blank?
    return uri unless youtube_embed_uri?(uri)

    parsed = parse_uri(uri)
    return uri unless parsed

    host = parsed.host.to_s.downcase.sub(/\Awww\./, "")
    video_id = extract_youtube_video_id(parsed, host)
    return uri unless valid_youtube_video_id?(video_id)

    watch_url = "https://www.youtube.com/watch?v=#{video_id}"
    start_seconds = extract_youtube_start_seconds(parsed)
    return watch_url unless start_seconds&.positive?

    "#{watch_url}&t=#{start_seconds}s"
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
      content.present?,
      applet.present? && !applet.marked_for_destruction?
    ].count(true)
    if payloads > 1
      errors.add(:base, "Only one payload variety (File, URI, Text, or Applet) can be present.")
    end
  end

  def normalize_youtube_uri
    return if uri.blank?

    self.uri = uri.to_s.strip
    embed_uri = normalized_youtube_embed_uri(uri)
    self.uri = embed_uri if embed_uri.present?
  end

  def youtube_uri_must_be_embed
    return if uri.blank?
    return unless youtube_url?(uri)
    return if youtube_embed_uri?(uri)

    errors.add(:uri, "YouTube URLs must use a valid embed-compatible video link.")
  end

  def normalized_youtube_embed_uri(raw_uri)
    parsed = parse_uri(raw_uri)
    return nil unless parsed

    host = parsed.host.to_s.downcase.sub(/\Awww\./, "")
    video_id = extract_youtube_video_id(parsed, host)
    return nil unless valid_youtube_video_id?(video_id)

    embed_uri = "https://www.youtube.com/embed/#{video_id}"
    start_seconds = extract_youtube_start_seconds(parsed)
    return embed_uri unless start_seconds&.positive?

    "#{embed_uri}?start=#{start_seconds}"
  end

  def youtube_url?(raw_uri)
    parsed = parse_uri(raw_uri)
    return false unless parsed&.host.present?

    host = parsed.host.to_s.downcase.sub(/\Awww\./, "")
    host == "youtu.be" || youtube_domain_host?(host)
  end

  def youtube_embed_uri?(raw_uri)
    parsed = parse_uri(raw_uri)
    return false unless parsed&.host.present?

    host = parsed.host.to_s.downcase.sub(/\Awww\./, "")
    return false unless youtube_domain_host?(host)

    parsed.path.to_s.match?(%r{\A/embed/[\w-]{11}\z})
  end

  def extract_youtube_video_id(parsed_uri, host)
    params = URI.decode_www_form(parsed_uri.query.to_s).to_h
    path_segments = parsed_uri.path.to_s.split("/").reject(&:blank?)

    return path_segments.first if host == "youtu.be"
    return nil unless youtube_domain_host?(host)

    case path_segments.first
    when "watch"
      params["v"]
    when "embed", "shorts", "live"
      path_segments.second
    else
      nil
    end
  end

  def extract_youtube_start_seconds(parsed_uri)
    params = URI.decode_www_form(parsed_uri.query.to_s).to_h
    raw = params["start"].presence || params["t"].presence || params["time_continue"].presence
    return nil if raw.blank?

    parse_time_to_seconds(raw)
  end

  def parse_time_to_seconds(value)
    str = value.to_s.strip.downcase
    return str.to_i if str.match?(/\A\d+\z/)

    match = str.match(/\A(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?\z/)
    return nil unless match

    hours = match[1].to_i
    minutes = match[2].to_i
    seconds = match[3].to_i
    total = (hours * 3600) + (minutes * 60) + seconds
    total.positive? ? total : nil
  end

  def valid_youtube_video_id?(value)
    value.to_s.match?(/\A[\w-]{11}\z/)
  end

  def youtube_domain_host?(host)
    host == "youtube.com" ||
      host.end_with?(".youtube.com") ||
      host == "youtube-nocookie.com" ||
      host.end_with?(".youtube-nocookie.com")
  end

  def parse_uri(value)
    URI.parse(value.to_s)
  rescue URI::InvalidURIError
    nil
  end
end
