OpenAI.configure do |config|
  config.log_errors = (ENV["RAILS_ENV"] == "development")
  config.uri_base = ENV["OPENAI_API_BASE_URI"] # Not really needed since will be set by OpenaiApiService
  config.request_timeout = 60
end
