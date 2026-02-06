module OpenaiErrorHelper
  private

  def extract_openai_error_message(exception)
    response_body = exception.respond_to?(:body) ? exception.body : nil
    return exception.message if response_body.nil?
    Rails.logger.error "Error response body: #{response_body}"

    parsed = if response_body.is_a?(String)
      begin
        JSON.parse(response_body)
      rescue JSON::ParserError
        return response_body
      end
    else
      response_body
    end

    parsed = stringify_keys(parsed) if parsed.is_a?(Hash) || parsed.is_a?(Array)
    parsed = parsed.first if parsed.is_a?(Array)

    Rails.logger.debug "Parsed error response: #{parsed.inspect}"

    if parsed.is_a?(Hash) && parsed["error"].is_a?(Hash)
      message = parsed["error"]["message"] || parsed["error"]["status"] || exception.message
      raw = parsed.dig("error", "metadata", "raw")
      raw ? "#{message}: (#{raw})" : message
    else
      exception.message
    end
  end

  def stringify_keys(value)
    case value
    when Hash
      value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = stringify_keys(v) }
    when Array
      value.map { |v| stringify_keys(v) }
    else
      value
    end
  end
end
