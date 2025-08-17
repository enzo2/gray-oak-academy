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

# Test helpers: provide a minimal Class.stub implementation and route helpers used by integration tests.
# This keeps tests hermetic without adding extra test dependencies.
class Class
  def stub(name, value = nil, &block)
    raise ArgumentError, "block required" unless block_given?
    sc = class << self; self; end
    had = sc.method_defined?(name) || sc.private_method_defined?(name)
    orig = sc.instance_method(name) if had

    # Define a temporary singleton method that either calls the provided callable or returns the value.
    # The wrapper tries keyword and positional invocation to be robust against different call signatures.
    sc.define_method(name) do |*args, **kwargs, &mblk|
      if value.respond_to?(:call)
        begin
          value.call(*args, **kwargs, &mblk)
        rescue ArgumentError
          begin
            value.call(*args, &mblk)
          rescue ArgumentError
            value.call(&mblk)
          end
        end
      else
        value
      end
    end

    begin
      yield
    ensure
      if had
        # Restore original method
        sc.define_method(name, orig)
      else
        # Remove the temporary method
        sc.send(:remove_method, name) rescue nil
      end
    end
  end
end

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
  end
end

class ActionDispatch::IntegrationTest
  include IntegrationTestAuthenticationHelpers
  include IntegrationRouteHelpers
end
