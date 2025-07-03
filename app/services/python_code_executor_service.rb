require "net/http"
require "uri"
require "json"

class PythonCodeExecutorService
  TERRARIUM_URL = "http://terrarium:8080" # Runs in docker container

  def self.execute(code)
    uri = URI.parse(TERRARIUM_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.request_uri)
    req["Content-Type"] = "application/json"
    req.body = { code: code }.to_json
    res = http.request(req)
    if res.is_a?(Net::HTTPSuccess)
      # Returns format  { "output_files": [], "final_expression": 2, "success": true, "std_out": "", "std_err": "", "code_runtime": 16 }
      # For now let's remove any file output
      JSON.parse(res.body).except(:output_files, :code_runtime) # Return a hash
    else
      { error: "Terrarium error: #{res.code} #{res.body}" }
    end
  rescue => e
    { error: e.message }
  end
end
