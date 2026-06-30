source "https://rubygems.org"

# use docker compose to import env files
# gem "dotenv-rails", groups: [ :development, :test ]

gem "rails", github: "rails/rails", branch: "main" # edge Rails
gem "propshaft"
gem "pg" # Use postgresql as the database for Active Record
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[ windows jruby ]
# gem "async"

gem "puma"# , "< 8" # Use the Puma web server [https://github.com/puma/puma]
# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
# gem "thruster", require: false
# # Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
# gem "kamal", require: false

# Rails adapters
gem "solid_queue"
gem "solid_cable", github: "rails/solid_cable", branch: "main"  # revert upon next release
gem "solid_cache"
gem "image_processing", "~> 2.0"
gem "ruby-vips"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
# gem "requestjs-rails"
gem "tailwindcss-rails", "~> 4.0"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt"

# Utilities
gem "json_schemer"
gem "json-repair"
gem "rack-attack"
gem "devise", ">= 5"
# gem "devise-jwt"
gem "acts_as_list"
gem "neighbor"
gem "markdown_views"
gem "hotwire_combobox", github: "josefarias/hotwire_combobox", branch: "main"  # change back to release for production
gem "faraday-retry"

# when ready: https://github.com/excid3/action_push_web

gem "commonmarker"

# LLM API access/wrappers
gem "openai"

# gem "ruby_llm"   # could add this but maybe not necessary, we already have openai_api_service. also, lacks TTS
# https://github.com/rira100000000/ruby-gemini-api  a good ruby-openai style gem for gemini


# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  # gem "rack-mini-profiler"
  # gem "bullet"
end

group :test do
  gem "dotenv-rails"

  gem "minitest", "> 5"
  gem "minitest-mock"

  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  gem "ostruct"
end
