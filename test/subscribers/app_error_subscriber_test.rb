require "test_helper"

class AppErrorSubscriberTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

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
end
