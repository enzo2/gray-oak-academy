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
require "minitest/mock"

module IntegrationRouteHelpers
  # Minimal route helper fallbacks used by integration tests.
  def audio_messages_conversation_path(conversation)
    "/conversations/#{conversation.id}/audio_messages"
  end

  def transcribed_messages_conversation_path(conversation)
    "/conversations/#{conversation.id}/transcribed_messages"
  end

  def tts_stream_message_path(message)
    "/messages/#{message.id}/tts_stream"
  end

  def generate_outline_admin_course_path(course)
    "/admin/courses/#{course.id}/generate_outline"
  end
end

module IntegrationTestAuthenticationHelpers
  def sign_in(user, password: "password")
    post user_session_path, params: { user: { email: user.email, password: password } }
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

    # Assert that the block logs a message matching the given pattern
    def assert_logs_matching(pattern)
      old_logger = Rails.logger
      log_output = StringIO.new
      Rails.logger = Logger.new(log_output)

      yield

      assert_match pattern, log_output.string
    ensure
      Rails.logger = old_logger
    end
  end
end

class ActionDispatch::IntegrationTest
  include IntegrationTestAuthenticationHelpers
  include IntegrationRouteHelpers
end

# Load test support helpers (small modules under test/support/)
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

# Include TestSupport helpers into Integration and System test bases so they are available
# to integration/job/system tests without requiring them individually.
if defined?(TestSupport::SpeechStubs)
  ActionDispatch::IntegrationTest.include TestSupport::SpeechStubs
  ApplicationSystemTestCase.include TestSupport::SpeechStubs if defined?(ApplicationSystemTestCase)
end
