# AnalyticsSubscriber captures a bounded stream of business events emitted via
# Rails.event.notify(Events::*), for superuser-facing operational analytics.
#
# It follows the same generic EventReporter pattern as NotificationSubscriber:
# - consumes Events::Base payloads
# - does not require per-event handler methods
# - relies on config/notifications.yml definitions through event_object.definition
class AnalyticsSubscriber
  MAX_EVENTS = 1000

  def self.emit(event)
    new.emit(event)
  end

  def emit(event)
    event_object = event[:payload]
    return unless event_object.is_a?(Events::Base)
    return unless User.role_superuser.exists?

    definition = event_object.definition
    params = event_object.params.symbolize_keys

    record_event!(
      event_type: definition.name,
      category: definition.category,
      subject: definition.subject,
      message: (definition.message % params),
      link: event_object.link,
      recipient_ids: Array(event_object.recipient_ids),
      params: event_object.params,
      emitted_at: Time.current.iso8601
    )
  rescue StandardError => e
    Rails.logger.error "Error in AnalyticsSubscriber: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
  end

  private

  def record_event!(entry)
    app_setting = AppSetting.settings
    return unless app_setting

    app_setting.with_lock do
      log = (app_setting.log || {}).deep_dup
      events = Array(log["analytics_events"])
      events.unshift(entry.deep_stringify_keys)
      events = events.first(MAX_EVENTS)

      settings = app_setting.settings.deep_dup
      settings.delete("analytics_events")
      app_setting.update!(log: log.merge("analytics_events" => events), settings: settings)
    end
  end
end
