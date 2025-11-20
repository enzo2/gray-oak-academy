require "net/http"
require "uri"

class HttpJsonService
  def self.get(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Error fetching JSON from #{url}: #{e.message}")
    nil
  end
end
