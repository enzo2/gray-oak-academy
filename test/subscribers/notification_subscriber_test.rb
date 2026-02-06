require "test_helper"

class NotificationSubscriberTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    # Ensure settings for all relevant users
    users(:admin).create_setting! if users(:admin).setting.nil?
    users(:student).create_setting! if users(:student).setting.nil?
    users(:super_user).create_setting! if users(:super_user).setting.nil?
  end

  test "creates notification on user.signup" do
    superuser = users(:super_user)
    student = users(:student)

    assert_difference -> { Notification.count }, 1 do
      Rails.event.notify(Events::UserSignup.new(
        recipient_ids: superuser.id,
        link: "/admin/students",
        new_user_name: student.name,
        new_user_email: student.email,
        new_user_id: student.id
      ))
    end

    notification = Notification.last
    assert_equal "user.signup", notification.event_type
    assert_equal superuser.id, notification.recipient_id
    assert_equal "/admin/students", notification.link
  end

  test "creates notification and email on conversation.context_warning" do
    conversation = conversations(:student_generic_conversation)
    teacher = conversation.user.teacher # admin

    assert_difference -> { Notification.count }, 1 do
      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
        Rails.event.notify(Events::ConversationContextWarning.new(
          recipient_ids: teacher.id,
          link: "/conversations/#{conversation.id}",
          user_name: conversation.user.name,
          title: conversation.title
        ))
      end
    end

    notification = Notification.last
    assert_equal "conversation.context_warning", notification.event_type
    assert_equal teacher.id, notification.recipient_id
  end

  test "creates notification but NO email on lesson.complete" do
    student = users(:student)
    teacher = users(:admin)
    course = Course.create!(title: "Course 1", teacher: teacher, summary: "Description of course", grade_level: "1")
    lesson = Lesson.create!(title: "Lesson 1", course: course, goals: "Learn about notifications", approx_duration_min: 30)
    Enrollment.create!(course: course, student: student)
    lp = LessonProgress.create!(lesson: lesson, student: student)
    report = StudentReport.create!(student: student, teacher: teacher, reportable: lp, status: :completed, author_type: :teacher_written, progress_data: { summary: "Good" })

    assert_difference -> { Notification.count }, 1 do
      assert_no_enqueued_emails do
        Rails.event.notify(Events::LessonComplete.new(
          recipient_ids: teacher.id,
          link: "/admin/students/#{student.id}",
          student_name: student.name,
          lesson_title: lesson.title,
          report_id: report.id
        ))
      end
    end

    notification = Notification.last
    assert_equal "lesson.complete", notification.event_type
    assert_equal teacher.id, notification.recipient_id
  end

  test "delivers to multiple recipients" do
    superuser1 = users(:super_user)
    superuser2 = users(:admin) # Temporarily treat as another recipient

    assert_difference -> { Notification.count }, 2 do
      Rails.event.notify(Events::UserSignup.new(
        recipient_ids: [ superuser1.id, superuser2.id ],
        link: "/admin/students",
        new_user_name: "Test User",
        new_user_email: "test@example.com",
        new_user_id: 999
      ))
    end
  end

  test "respects user email preferences" do
    conversation = conversations(:student_generic_conversation)
    teacher = conversation.user.teacher

    # Disable email for 'important' category
    prefs = teacher.settings.notification_preferences.dup
    prefs["important"] ||= {}
    prefs["important"]["email"] = false
    teacher.settings.notification_preferences = prefs
    teacher.settings.save!

    assert_difference -> { Notification.count }, 1 do
      assert_no_enqueued_emails do
        Rails.event.notify(Events::ConversationContextWarning.new(
          recipient_ids: teacher.id,
          link: "/conversations/#{conversation.id}",
          user_name: conversation.user.name,
          title: conversation.title
        ))
      end
    end
  end

  test "raises error for missing required params" do
    # Events require recipient_ids plus the params defined in notifications.yml
    assert_raises(ArgumentError) do
      Events::UserSignup.new(
        recipient_ids: [ 1 ],
        link: "/test"
        # Missing: new_user_name, new_user_email, new_user_id
      )
    end
  end

  test "skips notification if recipient not found" do
    # Should not raise, just skip
    assert_no_difference -> { Notification.count } do
      Rails.event.notify(Events::UserSignup.new(
        recipient_ids: [ -999 ], # Non-existent user
        link: "/admin/students",
        new_user_name: "Test",
        new_user_email: "test@example.com",
        new_user_id: 1
      ))
    end
  end

  test "student profile email includes snapshot and absolute link" do
    teacher = users(:admin)
    prefs = teacher.settings.notification_preferences.deep_dup
    prefs["student_progress"] ||= {}
    prefs["student_progress"]["email"] = true
    teacher.settings.notification_preferences = prefs
    teacher.settings.save!

    assert_difference -> { Notification.count }, 1 do
      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
        Rails.event.notify(Events::StudentProfileGenerated.new(
          recipient_ids: teacher.id,
          link: "/admin/students/1?active_tab=journal#student_report_108",
          student_name: "Lucas Policastro",
          current_snapshot: "Strong momentum in reading fluency.",
          report_id: 108
        ))
      end
    end

    perform_enqueued_jobs only: ActionMailer::MailDeliveryJob
    mail = ActionMailer::Base.deliveries.last
    body = mail.html_part&.body&.decoded || mail.body.decoded

    assert_match(/Current snapshot:/, body)
    assert_includes body, "Strong momentum in reading fluency."
    assert_includes body, "http://example.com/admin/students/1?active_tab=journal#student_report_108"
  end
end
