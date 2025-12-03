class UserNotificationMailer < ApplicationMailer
  def new_notification(recipient:, subject:, message:, link: nil)
    @recipient = recipient
    @message = message
    @link = link

    mail(
      to: @recipient.email,
      subject: subject || "New Notification"
    )
  end
end
