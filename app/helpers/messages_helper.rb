module MessagesHelper
  # Student-facing summary of an applet's reported data. Prefers the applet's own
  # `summary` sentence; otherwise falls back to a humanized key/value line.
  # Stored data is typically a JSON string (see MessagesController#bounded_applet_data).
  def applet_result_summary(data)
    parsed = data.is_a?(String) ? safe_parse_json(data) : data

    if parsed.is_a?(Hash) && parsed["summary"].is_a?(String) && parsed["summary"].strip.present?
      return parsed["summary"].strip.truncate(400)
    end

    case parsed
    when nil then ""
    when Hash
      parsed.first(4).map { |k, v| "#{k.to_s.humanize}: #{v.is_a?(Enumerable) ? v.to_json : v}" }.join(" · ").truncate(160)
    when Array then "#{parsed.size} #{'item'.pluralize(parsed.size)}"
    else parsed.to_s.truncate(160)
    end
  end

  private

  def safe_parse_json(str)
    JSON.parse(str)
  rescue JSON::ParserError
    str
  end
end
