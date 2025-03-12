OpenAI.configure do |config|
  config.log_errors = (ENV["RAILS_ENV"] == "development")
  config.uri_base = ENV["OPENAI_API_BASE_URI"]
  config.request_timeout = ENV["RAILS_ENV"] == "development" ? 120 : 20
end
