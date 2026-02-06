require "uri"

class UserNotificationMailer < ApplicationMailer
  def new_notification(recipient:, subject:, message:, link: nil, definition_name: nil, notification_params: {})
    @recipient = recipient
    @message = message
    @link = absolute_link(link)
    @notification_params = (notification_params || {}).deep_symbolize_keys
    @override_body_partial = override_body_partial_for(definition_name)

    mail(
      to: @recipient.email,
      subject: subject || "New Notification"
    )
  end

  private

  def override_body_partial_for(definition_name)
    return nil if definition_name.blank?

    partial_name = "#{definition_name.to_s.tr('.', '_')}_body"
    partial_path = "user_notification_mailer/#{partial_name}"
    return partial_path if lookup_context.exists?(partial_path, [], true)

    nil
  end

  def absolute_link(link)
    return link if link.blank?
    return link if absolute_url?(link)

    defaults = Rails.application.config.action_mailer.default_url_options || {}
    host = defaults[:host].presence
    return link unless host

    protocol = defaults[:protocol].presence || "http"
    port = defaults[:port]
    base = +"#{protocol}://#{host}"
    base << ":#{port}" if port.present?

    begin
      URI.join("#{base}/", link.sub(%r{\A/}, "")).to_s
    rescue StandardError
      "#{base}#{link.start_with?("/") ? link : "/#{link}"}"
    end
  end

  def absolute_url?(value)
    uri = URI.parse(value)
    uri.scheme.present? && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
