# NotificationSubscriber handles delivery of notifications (in-app and email)
# for events emitted via Rails.event.notify(Events::*).
#
# The subscriber is generic: it extracts recipient_ids, link, and params from
# the event object, then creates notifications and sends emails based on each
# recipient's preferences.
#
# Adding a new notification type requires:
#   1. Add the event definition to config/notifications.yml
#   2. Fire the event from the appropriate model with recipient_ids, link, and required params
#
# No changes to this subscriber are needed for new event types.
class NotificationSubscriber
  def self.emit(event)
    new.emit(event)
  end

  def emit(event)
    event_object = event[:payload]

    unless event_object.is_a?(Events::Base)
      # Prevented by subscription filter, but defensive check
      return
    end

    Rails.logger.debug "NotificationSubscriber processing: #{event_object.class.type_key}"

    # Deliver notification to each recipient
    User.where(id: event_object.recipient_ids).find_each do |recipient|
      deliver_to(
        recipient: recipient,
        event_object: event_object
      )
    end
  rescue StandardError => e
    Rails.logger.error "Error in NotificationSubscriber: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
  end

  private

  def deliver_to(recipient:, event_object:)
    definition = event_object.definition
    category = definition.category
    params = event_object.params.symbolize_keys
    link = event_object.link

    # In-App Notification
    if recipient.notifies_on?(category, "in_app")
      Rails.logger.debug "Creating in-app notification for User##{recipient.id} for event #{definition.name}"
      Notification.create!(
        recipient: recipient,
        event_type: definition.name,
        params: params,
        link: link
      )
    end

    # Email Notification
    if recipient.notifies_on?(category, "email")
      Rails.logger.debug "Sending email notification to User##{recipient.id} for event #{definition.name}"
      message_text = definition.message % params
      UserNotificationMailer.new_notification(
        recipient: recipient,
        subject: definition.subject,
        message: message_text,
        link: link
      ).deliver_later
    end
  end
end
