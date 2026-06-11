

Rails.application.config.to_prepare do
  # Dynamically generate Events::* classes based on Notification::Type definitions.
  # Each event type like "lesson.complete" becomes Events::LessonComplete.
  # Notification::Type (in app/models/notification.rb) is the single source of truth,
  # loading definitions from config/notifications.yml.
  Notification::Type.all.each_key do |key|
    # Convert "lesson.complete" => "LessonComplete"
    class_name = key.split(".").map(&:camelize).join

    # Skip if class already defined (e.g., in manual overrides)
    next if Events.const_defined?(class_name, false)

    klass = Class.new(Events::Base) do
      define_singleton_method(:type_key) { key }
    end

    Events.const_set(class_name, klass)
  end
end

# Register subscribers after initialization to ensure autoloading works
Rails.application.config.after_initialize do
  # Register the app error subscriber for system errors
  Rails.error.subscribe(AppErrorSubscriber.new)

  # Register the notification subscriber for business events.
  # Filter ensures we only process our explicit Events::Base objects,
  # ignoring internal Rails events (rendering, active_job, etc.)
  Rails.event.subscribe(NotificationSubscriber.new) do |event|
    event[:name].start_with?("Events::")
  end

  # Analytics subscriber consumes the same business events and records a
  # bounded analytics stream for superuser-facing operational insight.
  Rails.event.subscribe(AnalyticsSubscriber.new) do |event|
    event[:name].start_with?("Events::")
  end
end
