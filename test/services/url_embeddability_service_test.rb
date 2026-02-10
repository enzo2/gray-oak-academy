require "test_helper"

class UrlEmbeddabilityServiceTest < ActiveSupport::TestCase
  test "frame-ancestors wildcard subdomain is treated as blocking" do
    directive = "frame-ancestors https://*.example.com"
    assert UrlEmbeddabilityService.send(:frame_ancestors_blocks_iframe?, directive)
  end

  test "frame-ancestors https scheme is treated as permissive" do
    directive = "frame-ancestors https:"
    assert_not UrlEmbeddabilityService.send(:frame_ancestors_blocks_iframe?, directive)
  end
end
