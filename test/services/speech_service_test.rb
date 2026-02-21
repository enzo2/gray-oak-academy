require "test_helper"

class SpeechServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @conversation = conversations(:teacher_generic_conversation)
    AppSetting.settings.update!(
      provider_supported_api_id: supported_apis(:example_api).id,
      stt_method: "speech",
      stt_model: "transcribe-1"
    )
  end

  test "transcribe returns plain text from transcription response object" do
    fake_client = build_speech_client do |_params|
      Struct.new(:text).new("Hello from STT object")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = SpeechService.new(current_user: @user, conversation: @conversation)

      Tempfile.create([ "audio", ".wav" ]) do |file|
        assert_equal "Hello from STT object", service.transcribe(file)
      end
    end
  end

  test "transcribe sends a Pathname file part when given a Tempfile" do
    captured = {}
    fake_client = build_speech_client do |params|
      captured[:file] = params[:file]
      Struct.new(:text).new("ok")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = SpeechService.new(current_user: @user, conversation: @conversation)

      Tempfile.create([ "audio", ".wav" ]) do |file|
        file.write("abc")
        file.rewind
        service.transcribe(file)
      end
    end

    assert_instance_of Pathname, captured[:file]
    assert_predicate captured[:file].to_s, :present?
  end

  test "transcribe converts string file path to Pathname upload" do
    captured = {}
    fake_client = build_speech_client do |params|
      captured[:file] = params[:file]
      Struct.new(:text).new("ok")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = SpeechService.new(current_user: @user, conversation: @conversation)

      Tempfile.create([ "audio", ".wav" ]) do |file|
        file.write("abc")
        file.rewind
        service.send(:transcribe_via_speech_api, file.path)
      end
    end

    assert_instance_of Pathname, captured[:file]
    assert_predicate captured[:file].to_s, :present?
  end

  test "transcribe falls back to raw request when sdk response coercion fails" do
    captured = {}
    fake_client = build_speech_client do |_params|
      raise TypeError, "wrong element type String (expected array)"
    end
    fake_client.define_singleton_method(:request) do |**params|
      captured[:request] = params
      "Recovered transcript"
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = SpeechService.new(current_user: @user, conversation: @conversation)

      Tempfile.create([ "audio", ".wav" ]) do |file|
        file.write("abc")
        file.rewind
        assert_equal "Recovered transcript", service.transcribe(file)
      end
    end

    assert_equal :post, captured.dig(:request, :method)
    assert_equal "audio/transcriptions", captured.dig(:request, :path)
    assert_equal "text", captured.dig(:request, :body, :response_format)
    assert_instance_of Pathname, captured.dig(:request, :body, :file)
  end

  test "tts_stream surfaces unauthorized error when provider returns 401 without body" do
    AppSetting.settings.update!(tts_model: "tts-1", tts_voice: "alloy")
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("audio/speech") { [ 401, {}, "" ] }
    end
    conn = Faraday.new(url: "https://api.example.com/") do |builder|
      builder.response :raise_error
      builder.adapter :test, stubs
    end

    service = SpeechService.new(current_user: @user, conversation: @conversation)
    error = assert_raises(SpeechService::SpeechServiceError) do
      service.tts_stream("hello world", connection: conn) { |_chunk| }
    end

    assert_match(/unauthorized/i, error.message)
    stubs.verify_stubbed_calls
  end

  private

  def build_speech_client(&create_proc)
    transcriptions = Object.new
    transcriptions.define_singleton_method(:create) do |**params|
      create_proc.call(params)
    end

    audio = Object.new
    audio.define_singleton_method(:transcriptions) { transcriptions }

    client = Object.new
    client.define_singleton_method(:audio) { audio }

    client
  end
end
