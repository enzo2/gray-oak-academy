# Preview all emails at http://localhost:3000/rails/mailers/context_limit_mailer
class ContextLimitMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/context_limit_mailer/notify_admin
  def notify_admin
    ContextLimitMailer.notify_admin(Conversation.last)
  end
end
