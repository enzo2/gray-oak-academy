source "https://rubygems.org"

# use docker compose to import env files
# gem "dotenv-rails", groups: [ :development, :test ]

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "< 8.2"
gem "propshaft"
gem "pg" # Use postgresql as the database for Active Record
# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
# gem "thruster", require: false
gem "puma", "< 7" # Use the Puma web server [https://github.com/puma/puma]
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
# gem "kamal", require: false

# Rails adapters
gem "solid_queue"
gem "solid_cable"
gem "solid_cache"
gem "image_processing", "~> 1.2"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails", "~> 4.0"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt"

# Utilities
gem "json_schemer"
gem "json-repair"
gem "rack-attack", github: "rack/rack-attack", branch: "main" # Use main branch since last version is from 2023
gem "devise", github: "heartcombo/devise", branch: "main"  # use main for now until V5  is released
# gem "devise-jwt"
gem "acts_as_list"
gem "neighbor"
gem "markdown_views"
gem "hotwire_combobox"
gem "faraday-retry"

# when ready: https://github.com/excid3/action_push_web

# LLM API access/wrappers
gem "open_router"# , git: "https://github.com/enzo2/open_router.git" # Original gem had broken streaming
gem "ruby-openai", "< 8.4"
# gem "ruby_llm"   # could add this but it's not fully developed yet, eg. lacks xAI, TTS
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
end

group :test do
  gem "dotenv-rails"
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
