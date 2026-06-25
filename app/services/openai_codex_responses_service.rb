class OpenaiCodexResponsesService < OpenaiResponsesService
  private

  def provider_requires_stream_transport?
    true
  end

  def build_state_params(store:, previous_response_id:)
    { store: false }
  end

  def fallback_instructions
    format(CODEX_FALLBACK_INSTRUCTIONS_TEMPLATE, app_name: ENV["APP_NAME"].presence || "Gray Oak Academy")
  end

  def request_temperature_param(_temperature)
    {}
  end

  def responses_stream_for_provider(request_params, request_options_param)
    manual_codex_responses_stream(request_params, request_options_param)
  end

  def manual_codex_responses_stream(request_params, request_options_param)
    uri = URI.join(ensure_trailing_slash(@base_uri), "responses")
    payload = request_params.deep_dup
    payload[:stream] = true
    headers = {
      "Authorization" => "Bearer #{@access_token}",
      "Content-Type" => "application/json",
      "Accept" => "text/event-stream"
    }.merge(request_options_param.dig(:request_options, :extra_headers).to_h)

    Enumerator.new do |y|
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = client_timeout_seconds
      http.read_timeout = client_timeout_seconds

      request = Net::HTTP::Post.new(uri.request_uri)
      headers.each { |key, value| request[key] = value }
      request.body = payload.to_json

      http.request(request) do |response|
        if !response.is_a?(Net::HTTPSuccess)
          error_body = +""
          response.read_body { |chunk| error_body << chunk }
          raise codex_stream_error(
            status: response.code,
            content_type: response["Content-Type"],
            body: error_body
          )
        end

        content_type = response["Content-Type"].to_s
        buffer = +""
        saw_sse_frame = false
        response.read_body do |chunk|
          buffer << chunk
          event_hashes = drain_sse_events!(buffer)
          saw_sse_frame ||= event_hashes.present?
          event_hashes.each do |event_hash|
            y << event_hash
          end
        end

        event_hashes = drain_sse_events!(buffer, flush: true)
        saw_sse_frame ||= event_hashes.present?
        event_hashes.each do |event_hash|
          y << event_hash
        end

        if !saw_sse_frame
          Rails.logger.warn(
            "OpenaiResponsesService: Codex stream returned non-SSE content_type=#{content_type.inspect} body=#{buffer.first(240).inspect}"
          )
        end
      end
    end
  end

  # Classify a failed Codex stream response. A 429 usage_limit_reached means the
  # teacher's ChatGPT subscription is temporarily exhausted; surface a dedicated
  # error so callers can fall back to the shared background-agent provider.
  def codex_stream_error(status:, content_type:, body:)
    message = "Codex stream request failed: status=#{status} content_type=#{content_type} body=#{body.first(240).inspect}"
    if codex_usage_limit_response?(status: status, body: body)
      details = codex_usage_limit_details(body)
      BackgroundAgentConfigResolver::CodexUsageLimitError.new(
        message,
        resets_at: details[:resets_at],
        plan_type: details[:plan_type]
      )
    else
      OpenAiError.new(message)
    end
  end

  def codex_usage_limit_response?(status:, body:)
    return false unless status.to_s == "429"

    parsed = JSON.parse(body.to_s)
    parsed.is_a?(Hash) && parsed.dig("error", "type").to_s == "usage_limit_reached"
  rescue JSON::ParserError
    body.to_s.include?("usage_limit_reached")
  end

  # Pull the reset time and plan tier out of a usage-limit body so callers can
  # render teacher-facing text. Prefer the absolute resets_at; fall back to the
  # relative resets_in_seconds. Best-effort: a malformed body yields no details.
  def codex_usage_limit_details(body)
    parsed = JSON.parse(body.to_s)
    error = parsed.is_a?(Hash) ? parsed["error"].to_h : {}

    resets_at =
      if error["resets_at"].present?
        Time.zone.at(error["resets_at"].to_i)
      elsif error["resets_in_seconds"].present?
        Time.current + error["resets_in_seconds"].to_i.seconds
      end

    { resets_at: resets_at, plan_type: error["plan_type"].to_s.presence }
  rescue JSON::ParserError
    {}
  end

  def drain_sse_events!(buffer, flush: false)
    events = []
    normalized = buffer.gsub("\r\n", "\n")
    cursor = 0

    while (separator_index = normalized.index("\n\n", cursor))
      chunk = normalized[cursor...separator_index]
      events.concat(parse_sse_chunk(chunk))
      cursor = separator_index + 2
    end

    if flush
      remainder = normalized[cursor..]
      events.concat(parse_sse_chunk(remainder.to_s))
      buffer.clear
    else
      buffer.replace(normalized[cursor..].to_s)
    end

    events
  end

  def parse_sse_chunk(chunk)
    return [] if chunk.blank?

    event_name = nil
    data_lines = []

    chunk.each_line(chomp: true) do |line|
      next if line.blank? || line.start_with?(":")

      field, value = line.split(":", 2)
      value = value.to_s.sub(/\A /, "")
      case field
      when "event"
        event_name = value
      when "data"
        data_lines << value
      end
    end

    data = data_lines.join("\n")
    return [] if data.blank? || data == "[DONE]"

    parsed = JSON.parse(data)
    parsed["type"] ||= event_name if parsed.is_a?(Hash) && event_name.present?
    parsed.is_a?(Array) ? parsed : [ parsed ]
  rescue JSON::ParserError => e
    Rails.logger.warn("OpenaiResponsesService: failed to parse Codex SSE payload: #{e.message} chunk=#{chunk.first(240).inspect}")
    []
  end
end
