# Events module provides typed event classes for use with Rails.event.notify().
# Event definitions (required params, categories, messages) are defined in config/notifications.yml
# and loaded via Notification::Type, which is the single source of truth.
#
# Usage:
#   Rails.event.notify(Events::LessonComplete.new(
#     recipient_ids: [teacher.id],
#     student_name: "Alice",
#     lesson_title: "Math 101",
#     report_id: 123,
#     link: "/admin/students/1"
#   ))
#
# Events carry:
#   - recipient_ids: Array of user IDs who should receive the notification
#   - link: URL for the notification action (optional)
#   - All required params defined in notifications.yml for message interpolation

module Events
  class Base
    attr_reader :params, :recipient_ids, :link

    # All events require recipient_ids (who to notify) and optional link.
    # Additional params are validated against the Notification::Type definition.
    def initialize(recipient_ids:, link: nil, **params)
      @recipient_ids = Array(recipient_ids)
      @link = link
      @params = params.deep_stringify_keys

      # Validate against the canonical definition in Notification::Type
      definition.validate_params!(@params)
    end

    # Returns the Notification::Type definition for this event
    def definition
      @definition ||= Notification::Type.find(self.class.type_key)
    end

    # The event type key (e.g., "lesson.complete") - set by subclass
    def self.type_key
      raise NotImplementedError, "Subclass must define type_key"
    end

    # Serialize params for storage/transmission
    def as_json(options = {})
      @params.as_json(options).merge("type" => self.class.type_key)
    end
  end
end
