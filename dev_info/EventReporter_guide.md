# Structured Event Reporting in Gray Oak Academy

This guide covers the notification/event system built on Rails 8.1's `ActiveSupport::EventReporter` (`Rails.event`).

## Architecture Overview

The system uses a **Publish-Subscribe** pattern with these components:

1. **`config/notifications.yml`** - Single source of truth for event definitions
2. **`Notification::Type`** - Loads and validates event schemas
3. **`Events::*`** - Typed event classes (auto-generated from YAML)
4. **`NotificationSubscriber`** - Generic subscriber that handles all notification delivery
5. **Models** - Fire events with `Rails.event.notify()` including recipient resolution

### Key Principles

- **Single source of truth**: `notifications.yml` defines all event types, required params, categories, and message templates
- **Fat models**: Models determine who should be notified and fire events with pre-resolved `recipient_ids`
- **Generic subscriber**: `NotificationSubscriber` needs no per-event handler methods
- **Zero-touch additions**: Adding a new notification type requires only YAML + model code changes

---

## Adding a New Notification Type

### Step 1: Define in `config/notifications.yml`

```yaml
events:
  course.completed:
    category: student_progress  # Used for preference checking
    subject: "Course Completed"
    message: "%{student_name} completed course: %{course_title}."
    required_params:
      - student_name
      - course_title
      - enrollment_id
```

**Categories** control user notification preferences:
- `important` - Defaults to email + in-app
- `student_progress` - Defaults to in-app only

### Step 2: Fire the Event from the Model

```ruby
# In app/models/enrollment.rb
after_update_commit :notify_course_completed, if: -> { saved_change_to_status? && completed? }

private

def notify_course_completed
  return unless student.teacher # Only notify if there's a teacher
  
  Rails.event.notify(Events::CourseCompleted.new(
    recipient_ids: student.teacher.id,  # Who to notify (array or single ID)
    link: Rails.application.routes.url_helpers.admin_student_path(student),  # Action link
    student_name: student.name,
    course_title: course.title,
    enrollment_id: id
  ))
end
```

**That's it!** The `Events::CourseCompleted` class is auto-generated from YAML. The subscriber handles delivery automatically.

---

## How It Works

### Event Classes (`Events::*`)

Auto-generated in `config/initializers/events.rb` from `notifications.yml`:

```ruby
# Auto-generated - you don't write this:
module Events
  class CourseCompleted < Events::Base
    def self.type_key
      "course.completed"
    end
  end
end
```

All events inherit from `Events::Base` which:
- Requires `recipient_ids` (array or single ID)
- Validates params against `Notification::Type.find(type_key).required_params`
- Optionally accepts `link` for the notification action URL

### NotificationSubscriber

The generic subscriber:

1. Extracts `recipient_ids` from the event
2. Looks up each recipient
3. Checks their notification preferences
4. Creates `Notification` records (in-app)
5. Sends emails via `UserNotificationMailer`

```ruby
# Simplified flow:
def emit(event)
  event_object = event[:payload]
  
  event_object.recipient_ids.each do |recipient_id|
    recipient = User.find_by(id: recipient_id)
    next unless recipient
    
    if recipient.notifies_on?(category, "in_app")
      Notification.create!(...)
    end
    
    if recipient.notifies_on?(category, "email")
      UserNotificationMailer.new_notification(...).deliver_later
    end
  end
end
```

### User Preferences

Users control notifications via `Setting.notification_preferences`:

```ruby
# Default preferences (in Setting model):
{
  "important" => { "email" => true, "in_app" => true },
  "student_progress" => { "email" => false, "in_app" => true }
}
```

Check with: `user.notifies_on?("important", "email")`

---

## Event Firing Examples

### Single Recipient
```ruby
Rails.event.notify(Events::LessonComplete.new(
  recipient_ids: teacher.id,
  link: admin_student_path(student),
  student_name: student.name,
  lesson_title: lesson.title,
  report_id: report.id
))
```

### Multiple Recipients
```ruby
Rails.event.notify(Events::UserSignup.new(
  recipient_ids: User.role_superuser.pluck(:id),
  link: admin_students_path,
  new_user_name: user.name,
  new_user_email: user.email,
  new_user_id: user.id
))
```

---

## Error Reporting

System errors use a separate subscriber (`AppErrorSubscriber`) registered with `Rails.error`:

```ruby
# Automatically called on unhandled exceptions
Rails.error.subscribe(AppErrorSubscriber.new)
```

This sends email notifications to the webmaster with serialized error details.

---

## Testing

```ruby
# Test that an event creates notifications
test "creates notification on lesson complete" do
  assert_difference -> { Notification.count }, 1 do
    Rails.event.notify(Events::LessonComplete.new(
      recipient_ids: teacher.id,
      link: "/admin/students/1",
      student_name: "Alice",
      lesson_title: "Math 101",
      report_id: 1
    ))
  end
end

# Test validation
test "raises error for missing params" do
  assert_raises(ArgumentError) do
    Events::LessonComplete.new(
      recipient_ids: [1],
      link: "/test"
      # Missing required params!
    )
  end
end
```

---

## Future Extensions

### Adding an Analytics Subscriber

```ruby
# config/initializers/events.rb
Rails.event.subscribe(AnalyticsSubscriber.new) do |event|
  event[:payload].is_a?(Events::Base)
end
```

The same events can be consumed by multiple subscribers without model changes.

### Adding New Notification Channels

1. Add the channel preference to `Setting#notification_preferences` defaults
2. Update `NotificationSubscriber#deliver_to` to handle the new channel
3. Update user preference UI

---

## File Reference

| File | Purpose |
|------|---------|
| `config/notifications.yml` | Event definitions (source of truth) |
| `app/models/notification.rb` | Notification model + `Type` class |
| `config/initializers/events.rb` | Auto-generates `Events::*` classes, registers subscribers |
| `app/subscribers/notification_subscriber.rb` | Generic notification delivery |
| `app/subscribers/app_error_subscriber.rb` | System error notifications |
| `app/mailers/user_notification_mailer.rb` | User email delivery |
