# AppErrorSubscriber handles system errors reported via Rails.error.
# It sends email notifications to the webmaster for unhandled exceptions.
class AppErrorSubscriber
  MAX_EMAILS_PER_WINDOW = 10
  WINDOW_DURATION = 10.minutes

  def report(error, handled:, severity:, context:, source: nil)
    # We could filter by severity or handled status if needed.
    # For now, send all errors to webmaster.

    cache_key = "app_error_throttle:#{error.class.name}"
    count = Rails.cache.increment(cache_key, 1, expires_in: WINDOW_DURATION) || 1

    if count > MAX_EMAILS_PER_WINDOW
      Rails.logger.warn "AppErrorSubscriber throttled: #{error.class.name} (#{count} errors in #{WINDOW_DURATION.inspect})"
      return
    end

    # Serialize error details for the mailer job (errors can't be serialized directly)
    error_details = {
      class_name: error.class.name,
      message: error.message,
      backtrace: error.backtrace&.first(20)
    }

    # Ensure context values are serializable strings for ActiveJob
    safe_context = context.transform_values { |v| v.is_a?(String) ? v : v.inspect }

    ApplicationMailer.app_error_notification(
      error_details: error_details,
      context: safe_context,
      handled: handled,
      source: source
    ).deliver_later
  rescue StandardError => e
    # Fallback logging if email delivery fails
    Rails.logger.error "Failed to queue app error notification: #{e.message}"
    Rails.logger.error "Original error: #{error.class.name} - #{error.message}"
  end
end
