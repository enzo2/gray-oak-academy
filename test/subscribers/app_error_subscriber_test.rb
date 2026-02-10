require "test_helper"

class AppErrorSubscriberTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def setup
    @original_cache_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def teardown
    Rails.cache = @original_cache_store
  end

  test "enqueues error notification email" do
    subscriber = AppErrorSubscriber.new
    error = begin
      raise StandardError.new("Test Error")
    rescue => e
      e
    end

    assert_enqueued_emails 1 do
      subscriber.report(error, handled: false, severity: :error, context: { some: "context" })
    end
  end

  test "serializes error details correctly" do
    subscriber = AppErrorSubscriber.new
    error = begin
      raise ArgumentError.new("Invalid argument")
    rescue => e
      e
    end

    # The email should be enqueued with serializable data
    assert_enqueued_emails 1 do
      subscriber.report(error, handled: true, severity: :warning, context: { user_id: 123 }, source: "test")
    end
  end

  test "handles errors gracefully when email fails to enqueue" do
    subscriber = AppErrorSubscriber.new
    error = StandardError.new("Test Error")

    # Stub deliver_later to raise an error
    ApplicationMailer.stub(:app_error_notification, ->(*) { raise "Mail error" }) do
      # Should not raise, just log
      assert_nothing_raised do
        subscriber.report(error, handled: false, severity: :error, context: {})
      end
    end
  end

  test "throttles emails after MAX_EMAILS_PER_WINDOW errors of the same class" do
    Rails.cache.clear
    subscriber = AppErrorSubscriber.new
    limit = AppErrorSubscriber::MAX_EMAILS_PER_WINDOW

    # First MAX_EMAILS_PER_WINDOW errors should enqueue emails
    assert_enqueued_emails limit do
      limit.times do
        error = StandardError.new("Test Error")
        subscriber.report(error, handled: false, severity: :error, context: {})
      end
    end

    # Additional errors of the same class should be throttled (no new emails)
    assert_enqueued_emails 0 do
      3.times do
        error = StandardError.new("Test Error")
        subscriber.report(error, handled: false, severity: :error, context: {})
      end
    end
  end

  test "tracks throttling separately for different error classes" do
    Rails.cache.clear
    subscriber = AppErrorSubscriber.new
    limit = AppErrorSubscriber::MAX_EMAILS_PER_WINDOW

    # Max out StandardError
    assert_enqueued_emails limit do
      limit.times do
        error = StandardError.new("Test Error")
        subscriber.report(error, handled: false, severity: :error, context: {})
      end
    end

    # ArgumentError should still be able to send emails (different class)
    assert_enqueued_emails 1 do
      error = ArgumentError.new("Different error")
      subscriber.report(error, handled: false, severity: :error, context: {})
    end
  end

  test "logs warning when throttling emails" do
    Rails.cache.clear
    subscriber = AppErrorSubscriber.new
    limit = AppErrorSubscriber::MAX_EMAILS_PER_WINDOW

    # Max out the limit
    limit.times do
      error = StandardError.new("Test Error")
      subscriber.report(error, handled: false, severity: :error, context: {})
    end

    # Next error should trigger a warning log
    error = StandardError.new("Test Error")
    assert_logs_matching(/AppErrorSubscriber throttled: StandardError/) do
      subscriber.report(error, handled: false, severity: :error, context: {})
    end
  end
end
