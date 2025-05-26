require "open3"
require "rake"

# Ensure test credentials are set up before loading Rails environment
credentials_path = File.expand_path("../config/credentials/test.yml.enc", __dir__)
unless File.exist?(credentials_path)
  puts "Setting up test credentials via Rake API..."
  Rake.application.init
  Rake.application.load_rakefile
  ENV["RAILS_ENV"] = "test"
  Rake::Task["credentials:setup"].invoke
  abort "Created test credentials. Run tests again."
end

require "dotenv"
Dotenv.load ".env.test", overwrite: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module IntegrationTestAuthenticationHelpers
  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: user.password } }
    follow_redirect! if response.redirect?
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  include IntegrationTestAuthenticationHelpers
end
