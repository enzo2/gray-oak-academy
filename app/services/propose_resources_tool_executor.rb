require "json/repair"
require "net/http"
require "uri"
require "socket"
require "ipaddr"
require "securerandom"
require "tempfile"

class ProposeResourcesToolExecutor
  MAX_FILE_SIZE = 10.megabytes
  MAX_SEARCH_RESULTS = 20
  MAX_EXA_CONTENT_CHARS = 6000
  PDF_SIGNATURE = "%PDF-".b.freeze
  PRIVATE_OR_RESERVED_RANGES = [
    "0.0.0.0/8",
    "10.0.0.0/8",
    "100.64.0.0/10",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "172.16.0.0/12",
    "192.0.0.0/24",
    "192.0.2.0/24",
    "192.88.99.0/24",
    "192.168.0.0/16",
    "198.18.0.0/15",
    "198.51.100.0/24",
    "203.0.113.0/24",
    "224.0.0.0/4",
    "240.0.0.0/4",
    "::/128",
    "::1/128",
    "::ffff:0:0/96",
    "64:ff9b::/96",
    "100::/64",
    "2001:db8::/32",
    "fc00::/7",
    "fe80::/10",
    "ff00::/8"
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  def initialize(lesson_plan:, current_user:)
    @lesson_plan = lesson_plan
    @teacher = current_user
    @exa_service = ExaApiService.new(current_user: current_user)
    @pdf_artifacts = {}
    @image_artifacts = {}
  end

  def tool_definitions
    [
      exa_search_tool,
      exa_answer_tool,
      exa_content_tool,
      search_resources_tool,
      fetch_image_tool,
      fetch_pdf_tool,
      add_and_link_resource_tool
    ]
  end

  def execute(function_call)
    call_id = (function_call["call_id"] || function_call["id"]).to_s
    name = function_call["name"].to_s
    args = parse_arguments(function_call["arguments"])
    output = dispatch(name, args)

    {
      type: "function_call_output",
      call_id: call_id,
      output: output.is_a?(String) ? output : JSON.pretty_generate(output)
    }
  rescue StandardError => e
    {
      type: "function_call_output",
      call_id: call_id.presence || "unknown_call",
      output: "Tool execution error: #{e.message}"
    }
  end

  def cleanup_tempfiles
    @pdf_artifacts.values.each do |artifact|
      tempfile = artifact[:tempfile]
      next unless tempfile

      tempfile.close unless tempfile.closed?
      tempfile.unlink if tempfile.path && File.exist?(tempfile.path)
    rescue StandardError
      nil
    end
  end

  private

  def dispatch(name, args)
    case name
    when "exa_search"
      execute_exa_search(args)
    when "exa_answer"
      execute_exa_answer(args)
    when "exa_content"
      execute_exa_content(args)
    when "search_resources"
      execute_search_resources(args)
    when "fetch_image"
      execute_fetch_image(args)
    when "fetch_pdf"
      execute_fetch_pdf(args)
    when "add_and_link_resource"
      execute_add_and_link_resource(args)
    else
      raise OpenAiError, "Unsupported tool: #{name}"
    end
  end

  def parse_arguments(raw_arguments)
    raw = raw_arguments.presence || "{}"
    JSON.parse(raw)
  rescue JSON::ParserError
    repaired = JSON.repair(raw)
    JSON.parse(repaired)
  rescue JSON::ParserError, JSON::JSONRepairError
    raise OpenAiError, "Function call arguments must be valid JSON."
  end

  def execute_exa_search(args)
    query = args["query"].to_s.strip
    raise OpenAiError, "query is required." if query.blank?

    @exa_service.search(
      query: query,
      numResults: 6,
      contents: {
        text: { maxCharacters: 1400 }
      }
    )
  end

  def execute_exa_answer(args)
    query = args["query"].to_s.strip
    raise OpenAiError, "query is required." if query.blank?

    @exa_service.answer(query: query)
  end

  def execute_exa_content(args)
    urls = Array(args["urls"]).map(&:to_s).reject(&:blank?).uniq
    raise OpenAiError, "At least one URL is required." if urls.empty?

    max_characters = args["max_characters"].to_i
    max_characters = MAX_EXA_CONTENT_CHARS if max_characters <= 0
    max_characters = [ max_characters, MAX_EXA_CONTENT_CHARS ].min

    @exa_service.get_contents(
      urls: urls,
      text: { maxCharacters: max_characters }
    )
  end

  def execute_search_resources(args)
    limit = args["limit"].to_i
    limit = 10 if limit <= 0
    limit = [ limit, MAX_SEARCH_RESULTS ].min

    scope = Resource.where(teacher: @teacher).order(created_at: :desc)
    query = args["query"].to_s.strip
    if query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
      scope = scope.where(resource_search_predicate(pattern))
    end

    resources = scope.limit(limit)
    {
      resources: resources.map do |resource|
        {
          id: resource.id,
          category: resource.category,
          description: resource.description,
          approved: resource.approved,
          uri: resource.uri,
          has_file: resource.file.attached?,
          content_type: resource.file.attached? ? resource.file.content_type : nil,
          applet_id: resource.applet_id
        }
      end
    }
  end

  def resource_search_predicate(pattern)
    resources = Resource.arel_table
    lower_category = lower_coalesced(resources[:category])
    lower_description = lower_coalesced(resources[:description])
    lower_uri = lower_coalesced(resources[:uri])
    lower_tags = lower_coalesced(Arel::Nodes::NamedFunction.new("array_to_string", [ resources[:tags], Arel::Nodes.build_quoted(" ") ]))

    lower_category.matches(pattern)
      .or(lower_description.matches(pattern))
      .or(lower_uri.matches(pattern))
      .or(lower_tags.matches(pattern))
  end

  def lower_coalesced(node)
    Arel::Nodes::NamedFunction.new(
      "LOWER",
      [
        Arel::Nodes::NamedFunction.new("COALESCE", [ node, Arel::Nodes.build_quoted("") ])
      ]
    )
  end

  def execute_fetch_image(args)
    url = args["url"].to_s.strip
    resolved_ip = validate_public_https_url!(url)
    metadata = fetch_remote_metadata(url, resolved_ip: resolved_ip)
    content_type = metadata[:content_type].to_s.downcase
    size = metadata[:content_length]

    raise OpenAiError, "URL did not resolve to an image." unless content_type.start_with?("image/")
    raise OpenAiError, "Image exceeds #{MAX_FILE_SIZE / 1.megabyte}MB limit." if size && size > MAX_FILE_SIZE

    token = "img_#{SecureRandom.hex(8)}"
    @image_artifacts[token] = { url: url, content_type: content_type, size: size }

    {
      verified: true,
      token: token,
      url: url,
      content_type: content_type,
      bytes: size
    }
  end

  def execute_fetch_pdf(args)
    url = args["url"].to_s.strip
    resolved_ip = validate_public_https_url!(url)

    tempfile, content_type, bytesize = download_pdf(url, resolved_ip: resolved_ip)
    token = "pdf_#{SecureRandom.hex(8)}"
    @pdf_artifacts[token] = {
      url: url,
      tempfile: tempfile,
      content_type: content_type,
      bytesize: bytesize
    }

    {
      verified: true,
      token: token,
      url: url,
      content_type: content_type,
      bytes: bytesize
    }
  end

  def execute_add_and_link_resource(args)
    resource_type = args["resource_type"].to_s.strip.downcase
    description = args["description"].to_s.strip
    raise OpenAiError, "description is required." if description.blank?

    category = args["category"].to_s.strip.presence
    tags = Resource.normalize_tags(args["tags"])

    resource = case resource_type
    when "url", "image"
      url = args["url"].to_s.strip
      validate_public_https_url!(url)
      if resource_type == "image"
        image_token = args["image_token"].to_s.strip
        image_artifact = @image_artifacts[image_token]
        raise OpenAiError, "image_token is missing or invalid." unless image_artifact
        raise OpenAiError, "image_token does not match URL." unless image_artifact[:url] == url
      end

      Resource.create!(
        teacher: @teacher,
        category: category || (resource_type == "image" ? "Image" : "Web Resource"),
        description: description,
        uri: url,
        tags: tags,
        approved: false
      )
    when "text"
      content = args["content"].to_s.strip
      raise OpenAiError, "content is required for text resources." if content.blank?

      Resource.create!(
        teacher: @teacher,
        category: category || "Text",
        description: description,
        content: content,
        tags: tags,
        approved: false
      )
    when "pdf"
      pdf_token = args["pdf_token"].to_s.strip
      artifact = @pdf_artifacts[pdf_token]
      raise OpenAiError, "pdf_token is missing or invalid." unless artifact

      resource = Resource.create!(
        teacher: @teacher,
        category: category || "PDF",
        description: description,
        tags: tags,
        approved: false
      )

      filename = filename_for_url(artifact[:url], fallback: "resource.pdf")
      artifact[:tempfile].rewind
      resource.file.attach(
        io: artifact[:tempfile],
        filename: filename,
        content_type: "application/pdf"
      )
      resource.save!
      resource
    when "applet"
      applet_title = args["applet_title"].to_s.strip
      applet_code = args["applet_code"].to_s
      raise OpenAiError, "applet_title is required for applet resources." if applet_title.blank?
      raise OpenAiError, "applet_code is required for applet resources." if applet_code.strip.blank?
      if applet_code.strip.match?(/\A```(?:javascript|js)\b/i)
        raise OpenAiError, "applet_code must be raw JavaScript only. Do not include markdown fences."
      end

      syntax_check = NodeJsSyntaxChecker.check(applet_code)
      unless syntax_check[:valid]
        raise OpenAiError, "JavaScript syntax errors: #{syntax_check[:errors].join('; ')}"
      end

      applet = Applet.create!(user: @teacher, title: applet_title, code: applet_code)
      Resource.create!(
        teacher: @teacher,
        category: "Applet",
        description: description,
        tags: tags,
        approved: false,
        applet: applet
      )
    else
      raise OpenAiError, "resource_type must be one of: url, image, pdf, text, applet."
    end

    @lesson_plan.resources << resource unless @lesson_plan.resources.exists?(id: resource.id)

    {
      status: "ok",
      resource: {
        id: resource.id,
        category: resource.category,
        description: resource.description,
        approved: resource.approved,
        uri: resource.uri,
        has_file: resource.file.attached?,
        content_type: resource.file.attached? ? resource.file.content_type : nil
      }
    }
  end

  def exa_search_tool
    {
      type: "function",
      name: "exa_search",
      description: "Search the web for candidate educational resources.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query." }
        },
        required: [ "query" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def exa_answer_tool
    {
      type: "function",
      name: "exa_answer",
      description: "Get a grounded answer with citations from Exa.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Question to answer." }
        },
        required: [ "query" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def exa_content_tool
    {
      type: "function",
      name: "exa_content",
      description: "Fetch content from specific URLs to extract quotes, citations, and publication details.",
      parameters: {
        type: "object",
        properties: {
          urls: {
            type: "array",
            items: { type: "string" },
            description: "One or more absolute URLs."
          },
          max_characters: {
            type: [ "integer", "null" ],
            description: "Maximum characters to retrieve per URL (max 6000)."
          }
        },
        required: [ "urls", "max_characters" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def search_resources_tool
    {
      type: "function",
      name: "search_resources",
      description: "Search existing teacher resources to avoid duplicates before creating new records.",
      parameters: {
        type: "object",
        properties: {
          query: { type: [ "string", "null" ], description: "Free-text query across category, description, URL, and tags." },
          limit: { type: [ "integer", "null" ], description: "Maximum records to return (1..20)." }
        },
        required: [ "query", "limit" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def fetch_image_tool
    {
      type: "function",
      name: "fetch_image",
      description: "Verify that a public HTTPS URL points to an image and return a verification token.",
      parameters: {
        type: "object",
        properties: {
          url: { type: "string", description: "Public HTTPS image URL." }
        },
        required: [ "url" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def fetch_pdf_tool
    {
      type: "function",
      name: "fetch_pdf",
      description: "Download and verify a PDF from a public HTTPS URL (10MB max), then return a token for add_and_link_resource.",
      parameters: {
        type: "object",
        properties: {
          url: { type: "string", description: "Public HTTPS PDF URL." }
        },
        required: [ "url" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def add_and_link_resource_tool
    {
      type: "function",
      name: "add_and_link_resource",
      description: "Create a new resource, mark it as pending approval, and link it to the current lesson plan.",
      parameters: {
        type: "object",
        properties: {
          resource_type: {
            type: "string",
            enum: [ "url", "image", "pdf", "text", "applet" ],
            description: "Type of resource to create."
          },
          category: { type: [ "string", "null" ], description: "Optional category." },
          description: { type: "string", description: "Resource description shown to teachers/students." },
          tags: {
            type: [ "array", "null" ],
            items: { type: "string" },
            description: "Optional tags."
          },
          url: { type: [ "string", "null" ], description: "Required for url/image resources." },
          image_token: { type: [ "string", "null" ], description: "Required for image resources. Token returned by fetch_image." },
          pdf_token: { type: [ "string", "null" ], description: "Required for PDF resources. Token returned by fetch_pdf." },
          content: { type: [ "string", "null" ], description: "Required for text resources." },
          applet_title: { type: [ "string", "null" ], description: "Required for applet resources." },
          applet_code: { type: [ "string", "null" ], description: "Required for applet resources." }
        },
        required: [ "resource_type", "category", "description", "tags", "url", "image_token", "pdf_token", "content", "applet_title", "applet_code" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def filename_for_url(url, fallback:)
    path = URI.parse(url).path
    filename = File.basename(path.to_s)
    filename.present? && filename != "/" ? filename : fallback
  rescue StandardError
    fallback
  end

  def fetch_remote_metadata(url, resolved_ip:)
    uri = URI.parse(url)
    request = Net::HTTP::Head.new(uri.request_uri)
    response = perform_request(uri, request, resolved_ip: resolved_ip)

    if response.code.to_i >= 400 || response["Content-Type"].blank?
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Range"] = "bytes=0-1023"
      response = perform_request(uri, request, resolved_ip: resolved_ip)
    end

    {
      content_type: response["Content-Type"].to_s.split(";").first,
      content_length: response["Content-Length"]&.to_i
    }
  end

  def download_pdf(url, resolved_ip:)
    uri = URI.parse(url)
    request = Net::HTTP::Get.new(uri.request_uri)

    tempfile = Tempfile.new([ "resource_fetch", ".pdf" ])
    tempfile.binmode
    bytesize = 0
    content_type = nil

    with_http_client(uri, resolved_ip: resolved_ip, read_timeout: 20) do |http|
      http.request(request) do |response|
        unless response.code.to_i.between?(200, 299)
          raise OpenAiError, "Failed to fetch PDF (HTTP #{response.code})."
        end

        content_type = response["Content-Type"].to_s.split(";").first.to_s.downcase
        if response["Content-Length"].to_i > MAX_FILE_SIZE
          raise OpenAiError, "PDF exceeds #{MAX_FILE_SIZE / 1.megabyte}MB limit."
        end

        response.read_body do |chunk|
          bytesize += chunk.bytesize
          if bytesize > MAX_FILE_SIZE
            raise OpenAiError, "PDF exceeds #{MAX_FILE_SIZE / 1.megabyte}MB limit."
          end
          tempfile.write(chunk)
        end
      end
    end

    tempfile.rewind
    signature = tempfile.read(PDF_SIGNATURE.bytesize).to_s.b
    tempfile.rewind
    unless signature.start_with?(PDF_SIGNATURE)
      raise OpenAiError, "Downloaded file is not a valid PDF."
    end

    if content_type.present? && !content_type.include?("pdf")
      Rails.logger.warn("fetch_pdf content type mismatch: #{content_type}")
    end

    [ tempfile, content_type.presence || "application/pdf", bytesize ]
  rescue StandardError
    tempfile.close! if tempfile
    raise
  end

  def perform_request(uri, request, resolved_ip:)
    with_http_client(uri, resolved_ip: resolved_ip, read_timeout: 12) do |http|
      http.request(request)
    end
  end

  def with_http_client(uri, resolved_ip:, read_timeout:)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = resolved_ip
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 8
    http.read_timeout = read_timeout
    http.start { |client| yield client }
  end

  def validate_public_https_url!(url)
    raise OpenAiError, "URL is required." if url.blank?

    uri = URI.parse(url)
    raise OpenAiError, "URL must use HTTPS." unless uri.scheme.to_s.downcase == "https"
    raise OpenAiError, "URL host is missing." if uri.host.blank?

    host = uri.host
    ip_literal = parse_ip_literal(host)
    if ip_literal
      normalized = normalize_ipaddr(ip_literal)
      raise OpenAiError, "URL host resolves to a private or reserved IP." if private_or_reserved_ip?(normalized)
      return normalized.to_s
    end

    resolve_public_ip!(host)
  rescue URI::InvalidURIError
    raise OpenAiError, "Invalid URL format."
  rescue SocketError
    raise OpenAiError, "URL host did not resolve."
  end

  def resolve_public_ip!(host)
    addresses = Socket.getaddrinfo(host, nil, Socket::AF_UNSPEC, Socket::SOCK_STREAM).map { |entry| entry[3] }.uniq
    raise OpenAiError, "URL host did not resolve." if addresses.empty?

    parsed_ips = addresses.filter_map do |address|
      ip = parse_ip_literal(address)
      ip ? normalize_ipaddr(ip) : nil
    end.uniq(&:to_s)
    raise OpenAiError, "URL host did not resolve." if parsed_ips.empty?

    parsed_ips.each do |ip|
      raise OpenAiError, "URL host resolves to a private or reserved IP." if private_or_reserved_ip?(ip)
    end

    (parsed_ips.find(&:ipv4?) || parsed_ips.first).to_s
  end

  def parse_ip_literal(value)
    IPAddr.new(value)
  rescue StandardError
    nil
  end

  def normalize_ipaddr(ip)
    ip.ipv4_mapped? ? ip.native : ip
  end

  def private_or_reserved_ip?(ip)
    PRIVATE_OR_RESERVED_RANGES.any? { |range| range.include?(ip) }
  end
end
