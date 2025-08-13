require "uri"

module AdminHelper
  def format_api_provider(url)
    return "N/A" if url.blank?

    begin
      uri = URI.parse(url)
      uri.host || url # Return the original URL if the host is not parseable
    rescue URI::InvalidURIError
      url # Return the original URL if it's invalid
    end
  end

  def ensure_trailing_slash(url)
    return url if url.blank? || url.end_with?("/")
    "#{url}/"
  end
end
