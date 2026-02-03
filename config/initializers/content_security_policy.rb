# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, "https://cdn.jsdelivr.net", "https://fonts.gstatic.com"
    policy.img_src     :self, :data, :blob, :https
    policy.object_src  :none
    policy.script_src  :self, "https://cdn.jsdelivr.net", "https://esm.sh", :blob
    policy.style_src   :self, "https://cdn.jsdelivr.net", "https://fonts.googleapis.com", :unsafe_inline
    policy.connect_src :self, "https://cdn.jsdelivr.net", :data, "ws:", "wss:"
    policy.frame_src   :self, :https
    policy.media_src   :self, :blob, :data

    # Specify URI for violation reports
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Generate session nonces for permitted importmap, inline scripts, and inline styles.
  config.content_security_policy_nonce_generator = ->(request) do
    session = request&.session
    return SecureRandom.base64(16) unless session

    session[:csp_nonce] ||= SecureRandom.base64(16)
  end
  config.content_security_policy_nonce_directives = %w[script-src]

  # Automatically add `nonce` to `javascript_tag`, `javascript_include_tag`, and `stylesheet_link_tag`
  # if the corresponding directives are specified in `content_security_policy_nonce_directives`.
  config.content_security_policy_nonce_auto = true


  # Report violations without enforcing the policy.
  # config.content_security_policy_report_only = true
end
