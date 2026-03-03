require "test_helper"
require "tempfile"

class AudioTest < ActiveSupport::TestCase
  test "to_base64_wav uses AudioConverter and base64_for_LLM wraps payload" do
    audio = Audio.new

    mock_file = Object.new
    mock_file.define_singleton_method(:attached?) { true }
    mock_file.define_singleton_method(:open) do |&blk|
      Tempfile.open([ "audio", ".wav" ]) do |file|
        file.binmode
        file.write("RIFFTEST")
        file.rewind
        blk.call(file)
      end
    end
    audio.define_singleton_method(:file) { mock_file }

    AudioConverter.stub(:convert_to_base64_wav, "BASE64AUDIO") do
      assert_equal "BASE64AUDIO", audio.to_base64_wav
      assert_equal({ data: "BASE64AUDIO", format: "wav" }, audio.base64_for_LLM)
    end
  end
end
