require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  def setup
    @admin = users(:admin)
    @conversation = conversations(:teacher_generic_conversation)
  end

  test "csp allows applet imports blob modules and esm network fetches" do
    sign_in @admin

    get conversation_path(@conversation)
    policy = response.headers["Content-Security-Policy"]

    assert policy.present?, "Expected Content-Security-Policy header to be set"

    script_sources = extract_csp_sources(policy, "script-src")
    assert_includes script_sources, "https://esm.sh"
    assert_includes script_sources, "blob:"

    connect_sources = extract_csp_sources(policy, "connect-src")
    assert_includes connect_sources, "https://esm.sh"
  end

  test "csp nonce remains stable across turbo navigation requests" do
    sign_in @admin

    get conversation_path(@conversation)
    first_nonce = extract_meta_nonce(response.body)
    assert first_nonce.present?, "Expected csp-nonce meta tag to be present"

    get notifications_path
    second_nonce = extract_meta_nonce(response.body)
    assert second_nonce.present?, "Expected csp-nonce meta tag to be present"

    assert_equal first_nonce, second_nonce, "Expected CSP nonce to remain stable across requests in the same session"
  end

  private

  def extract_csp_sources(policy, directive)
    directives = policy.split(";").map(&:strip)
    entry = directives.find { |item| item.start_with?(directive) }
    return [] unless entry

    entry.sub(directive, "").split(/\s+/).reject(&:empty?)
  end

  def extract_meta_nonce(html)
    html[/<meta name="csp-nonce" content="([^"]+)"/, 1]
  end
end
