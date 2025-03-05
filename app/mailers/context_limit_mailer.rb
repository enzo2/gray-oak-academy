class ContextLimitMailer < ApplicationMailer
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.context_limit_mailer.notify_admin.subject
  #
  def notify_admin(conversation)
    Rails.logger.debug "Sending context limit warning email to admin"

    @conversation = conversation

    user = conversation.user
    teacher = user.teacher
    admin_email = teacher ? teacher.email : user.email

    mail(
      to: admin_email,
      from: ENV.fetch("WEBMASTER_EMAIL_ADDRESS"),
      subject: "Context Limit Warning"
    )
  end
end
