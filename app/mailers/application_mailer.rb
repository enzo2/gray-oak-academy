class ApplicationMailer < ActionMailer::Base
  default from: ENV["WEBMASTER_EMAIL_ADDRESS"]
  layout "mailer"
  before_action :attach_brand_logo

  # Send app error notification email.
  # @param error_details [Hash] Serialized error info with :class_name, :message, :backtrace
  # @param context [Hash] Additional context from Rails.error
  # @param handled [Boolean] Whether the error was rescued
  # @param source [String] Source identifier (optional)
  def app_error_notification(error_details:, context:, handled:, source:)
    @error_details = error_details
    @context = context
    @handled = handled
    @source = source

    mail(
      to: ENV["WEBMASTER_EMAIL_ADDRESS"],
      subject: "[#{ENV.fetch('APP_NAME', 'Gray Oak Academy')}] Application Error: #{error_details[:class_name]}"
    )
  end

  private

  def attach_brand_logo
    return if attachments["logo_mailer_icon.png"].present?

    logo_path = Rails.root.join("app/assets/images/logo_mailer_icon.png")
    return unless File.exist?(logo_path)

    attachments.inline["logo_mailer_icon.png"] = File.binread(logo_path)
  end
end
