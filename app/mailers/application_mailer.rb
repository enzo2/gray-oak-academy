class ApplicationMailer < ActionMailer::Base
  default from: ENV["WEBMASTER_EMAIL_ADDRESS"]
  layout "mailer"
end
