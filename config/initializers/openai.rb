OpenAI.configure do |config|
  config.log_errors = (ENV["RAILS_ENV"] == "development")
  config.uri_base = ENV["OPENAI_API_BASE_URI"]
  config.request_timeout = 10 # Aggressive timeout since nobody got time for that. Increase if you need to use reasoning models
end
