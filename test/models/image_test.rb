require "test_helper"
require "base64"

class ImageTest < ActiveSupport::TestCase
  test "to_base64 encodes variant download and base64_for_LLM builds data URI" do
    image = Image.new

    mock_file = Object.new
    mock_file.define_singleton_method(:attached?) { true }

    mock_variant = Object.new
    mock_variant.define_singleton_method(:processed) { mock_variant }
    mock_variant.define_singleton_method(:download) { "IMAGEDATA" }
    mock_file.define_singleton_method(:variant) { |_args| mock_variant }

    image.define_singleton_method(:file) { mock_file }
    image.define_singleton_method(:content_type) { "image/png" }

    encoded = Base64.strict_encode64("IMAGEDATA")
    assert_equal encoded, image.to_base64
    assert_equal "data:image/png;base64,#{encoded}", image.base64_for_LLM
  end
end
