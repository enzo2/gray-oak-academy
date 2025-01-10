OpenAI.configure do |config|
  config.log_errors = (ENV["RAILS_ENV"] == "development")
  config.uri_base = "https://openrouter.ai/api"
end
