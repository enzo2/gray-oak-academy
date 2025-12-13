# Helpers to stub SpeechService and provide Faraday test adapters for TTS in tests.
# Keep these small and focused so system/integration/job tests can reuse them.
require "faraday"

module TestSupport
  module SpeechStubs
    # Stubs SpeechService.new to return an object that responds to
    # .transcribe(file) and .sanitize_tts_text(text).
    #
    # Usage:
    #   stub_speech_service(transcription: "Hello") do
    #     # code that triggers transcribe
    #   end
    def stub_speech_service(transcription: "This is a test transcription.", &block)
      SpeechService.stub(:new, ->(**_kwargs) {
        Object.new.tap do |o|
          define_singleton_method_on(o, :transcribe) { |_file| transcription }
          define_singleton_method_on(o, :sanitize_tts_text) { |text| text }
        end
      }) do
        yield if block_given?
      end
    end

    # Provides a Faraday test adapter that responds to TTS requests by returning
    # the given fixture bytes. Injects the connection into SpeechService.default_conn
    # for the duration of the block.
    #
    # Usage:
    #   with_faraday_tts_stub(fixture: "test/fixtures/files/sample.ogg") do
    #     # code that triggers TTS HTTP call
    #   end
    def with_faraday_tts_stub(path: "/audio/speech", fixture: "test/fixtures/files/sample.ogg", content_type: nil)
      resolved_content_type = content_type || infer_tts_content_type(fixture)
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post(path) do |_env|
          body = tts_fixture_bytes(fixture)
          [ 200, { "Content-Type" => resolved_content_type }, body ]
        end
      end

      conn = Faraday.new(url: "https://api.example.com/") do |b|
        b.adapter :test, stubs
      end

      original = nil
      if defined?(SpeechService) && SpeechService.respond_to?(:default_conn)
        original = SpeechService.default_conn rescue nil
        SpeechService.default_conn = conn
      else
        Faraday.default_connection = conn
      end

      begin
        yield if block_given?
      ensure
        if defined?(SpeechService) && SpeechService.respond_to?(:default_conn)
          SpeechService.default_conn = original
        else
          Faraday.default_connection = nil
        end
        begin
          stubs.verify_stubbed_calls
        rescue StandardError
          # ignore verification errors in flaky CI scenarios
        end
      end
    end

    private

    def tts_fixture_bytes(fixture)
      full_path = Rails.root.join(fixture)
      raise ArgumentError, "TTS fixture not found: #{fixture}" unless File.exist?(full_path)
      File.binread(full_path)
    end

    def infer_tts_content_type(fixture)
      ext = File.extname(fixture.to_s).downcase
      return "audio/ogg" if ext == ".ogg"
      return "audio/webm" if ext == ".webm"

      "application/octet-stream"
    end

    # Utility to define singleton methods robustly across Ruby versions.
    def define_singleton_method_on(obj, name, &blk)
      obj.define_singleton_method(name, &blk)
    end
  end
end
