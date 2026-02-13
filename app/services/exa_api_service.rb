require "json"
require "net/http"
require "timeout"
require "uri"

class ExaApiService
  DEFAULT_BASE_URI = "https://api.exa.ai/"
  DEFAULT_RESEARCH_MODEL = "exa-research"
  TERMINAL_RESEARCH_STATUSES = %w[completed failed cancelled canceled].freeze
  DEFAULT_OPEN_TIMEOUT_SECONDS = 8
  DEFAULT_READ_TIMEOUT_SECONDS = 30
  DEFAULT_WRITE_TIMEOUT_SECONDS = 30
  DEFAULT_MAX_RETRIES = 2
  RETRYABLE_STATUS_CODES = [ 408, 409, 425, 429, 500, 502, 503, 504 ].freeze
  NETWORK_ERRORS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Timeout::Error,
    EOFError,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    Errno::ETIMEDOUT,
    SocketError
  ].freeze

  def initialize(api_key: nil, base_uri: nil, research_model: nil, current_user: nil, conversation: nil, log_completion: true)
    app_setting = AppSetting.settings
    @api_key = api_key.presence || app_setting&.exa_api_key.presence || ENV["EXA_API_KEY"]
    @base_uri = ensure_trailing_slash(base_uri.presence || DEFAULT_BASE_URI)
    @research_model = research_model.presence || app_setting&.exa_research_model.presence || DEFAULT_RESEARCH_MODEL
    @current_user = current_user
    @conversation = conversation
    @log_completion = log_completion

    raise OpenAiError, "Exa API key is not configured." if @api_key.blank?
  end

  # POST /search
  def search(query:, **options)
    raise OpenAiError, "query is required for Exa search." if query.to_s.strip.blank?

    merged_options = default_search_options.deep_merge(options.compact)
    response = post_json("/search", { query: query }.merge(merged_options))
    log_completion_if_possible(response, model: "exa-search")
    response
  end

  # POST /answer
  def answer(query:, **options)
    raise OpenAiError, "query is required for Exa answer." if query.to_s.strip.blank?

    response = post_json("/answer", { query: query }.merge(options.compact))
    log_completion_if_possible(response, model: "exa-answer")
    response
  end

  # POST /contents
  def get_contents(urls:, **options)
    normalized_urls = Array(urls).map(&:to_s).reject(&:blank?).uniq
    raise OpenAiError, "At least one URL is required for Exa contents." if normalized_urls.blank?

    response = post_json("/contents", { urls: normalized_urls }.merge(options.compact))
    log_completion_if_possible(response, model: "exa-contents")
    response
  end

  # POST /research/v1
  def create_research(instructions:, model: nil, output_schema: nil)
    raise OpenAiError, "instructions are required for Exa research." if instructions.to_s.strip.blank?

    payload = {
      model: model.presence || @research_model,
      instructions: instructions
    }
    payload[:outputSchema] = output_schema if output_schema.present?

    response = post_json("/research/v1", payload)
    log_completion_if_possible(response, model: payload[:model])
    response
  end

  # GET /research/v1/:id
  def get_research(research_id:, stream: nil, events: nil, log_completion: true)
    raise OpenAiError, "research_id is required." if research_id.to_s.strip.blank?

    query = {}
    query[:stream] = stream unless stream.nil?
    query[:events] = events if events.present?

    response = get_json("/research/v1/#{research_id}", query: query)
    log_completion_if_possible(response, model: response["model"] || @research_model) if log_completion
    response
  end

  # GET /research/v1
  def list_research(cursor: nil, limit: nil)
    query = {}
    query[:cursor] = cursor if cursor.present?
    query[:limit] = limit if limit.present?

    response = get_json("/research/v1", query: query)
    log_completion_if_possible(response, model: @research_model)
    response
  end

  # Poll research task until terminal status.
  def wait_for_research(research_id:, timeout_seconds: 600, poll_interval_seconds: 3)
    deadline = Time.current + timeout_seconds

    loop do
      response = get_research(research_id: research_id, log_completion: false)
      yield(response) if block_given?
      status = response["status"].to_s.downcase

      if TERMINAL_RESEARCH_STATUSES.include?(status)
        log_completion_if_possible(response, model: response["model"] || @research_model)
        return response
      end

      if Time.current >= deadline
        raise OpenAiError, "Exa research timed out after #{timeout_seconds} seconds."
      end

      sleep(poll_interval_seconds)
    end
  end

  # POST /responses (OpenAI-compatible endpoint hosted by Exa)
  def responses_research(input:, model: nil, **options)
    raise OpenAiError, "input is required for Exa responses research." if input.blank?

    payload = {
      model: model.presence || @research_model,
      input: input
    }.merge(options.compact)

    response = post_json("/responses", payload)
    log_completion_if_possible(response, model: payload[:model])
    response
  end

  private

  def get_json(path, query: {})
    request_json(method: :get, path: path, query: query)
  end

  def post_json(path, payload)
    request_json(method: :post, path: path, payload: payload)
  end

  def request_json(method:, path:, payload: nil, query: {})
    uri = URI.join(@base_uri, path.delete_prefix("/"))
    uri.query = URI.encode_www_form(query) if query.present?

    attempts = 0
    loop do
      attempts += 1
      http = build_http_client(uri)
      request = build_request(method: method, uri: uri, payload: payload)
      response = http.request(request)
      parsed = parse_json(response.body)

      status = response.code.to_i
      return parsed if status.between?(200, 299)

      if should_retry_request?(method: method, status: status, attempts: attempts)
        sleep(retry_delay_seconds(attempts))
        next
      end

      error_message = parsed.dig("error", "message").presence || parsed["message"].presence || "HTTP #{response.code}"
      raise OpenAiError, "Exa API request failed (#{response.code}): #{error_message}"
    rescue *NETWORK_ERRORS => e
      if should_retry_network_error?(method: method, attempts: attempts)
        sleep(retry_delay_seconds(attempts))
        next
      end

      Rails.logger.error "Exa API network error: #{e.class}: #{e.message}"
      raise OpenAiError, "Exa API request failed: #{e.message}"
    end
  rescue OpenAiError
    raise
  rescue StandardError => e
    Rails.logger.error "Exa API request error: #{e.message}"
    raise OpenAiError, "Exa API request failed: #{e.message}"
  end

  def build_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = DEFAULT_OPEN_TIMEOUT_SECONDS if http.respond_to?(:open_timeout=)
    http.read_timeout = DEFAULT_READ_TIMEOUT_SECONDS if http.respond_to?(:read_timeout=)
    http.write_timeout = DEFAULT_WRITE_TIMEOUT_SECONDS if http.respond_to?(:write_timeout=)
    http
  end

  def retryable_status_code?(status)
    RETRYABLE_STATUS_CODES.include?(status)
  end

  def retryable_method?(method)
    method.to_sym == :get
  end

  def should_retry_request?(method:, status:, attempts:)
    retryable_method?(method) && retryable_status_code?(status) && attempts <= DEFAULT_MAX_RETRIES
  end

  def should_retry_network_error?(method:, attempts:)
    retryable_method?(method) && attempts <= DEFAULT_MAX_RETRIES
  end

  def retry_delay_seconds(attempt)
    [ 0.25 * (2**(attempt - 1)), 2.0 ].min
  end

  def build_request(method:, uri:, payload:)
    request =
      case method
      when :get
        Net::HTTP::Get.new(uri.request_uri)
      when :post
        Net::HTTP::Post.new(uri.request_uri)
      else
        raise ArgumentError, "Unsupported HTTP method: #{method}"
      end

    request["x-api-key"] = @api_key
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = payload.to_json if payload.present?
    request
  end

  def parse_json(body)
    return {} if body.blank?
    JSON.parse(body)
  rescue JSON::ParserError
    { "raw" => body.to_s }
  end

  def ensure_trailing_slash(url)
    return url if url.blank? || url.end_with?("/")
    "#{url}/"
  end

  def default_search_options
    {
      contents: {
        highlights: {
          maxCharacters: 1200
        }
      }
    }
  end

  def log_completion_if_possible(response, model:)
    return unless @log_completion

    total_cost = extract_total_cost(response)
    return unless total_cost.present?

    user = @current_user || @conversation&.user
    return unless user

    Completion.create!(
      user: user,
      conversation: @conversation,
      model: model,
      api_provider: @base_uri,
      reasoning_tokens: extract_reasoning_tokens(response),
      total_cost: total_cost
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log Exa completion usage: #{e.message}"
  end

  def extract_total_cost(response)
    cost = response["costDollars"]
    return nil unless cost.is_a?(Hash)

    cost["total"]
  end

  def extract_reasoning_tokens(response)
    cost = response["costDollars"]
    return nil unless cost.is_a?(Hash)

    cost["reasoningTokens"]&.to_i
  end
end
