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

  test "gpt-transcribe requests JSON response format" do
    AppSetting.settings.update!(stt_model: "gpt-transcribe")
    captured = {}
    fake_client = build_speech_client do |params|
      captured.merge!(params)
      Struct.new(:text).new("Hello from GPT-Transcribe")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = SpeechService.new(current_user: @user, conversation: @conversation)

      Tempfile.create([ "audio", ".wav" ]) do |file|
        assert_equal "Hello from GPT-Transcribe", service.transcribe(file)
      end
    end

    assert_equal "gpt-transcribe", captured[:model]
    assert_equal "json", captured[:response_format]
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

  test "OpenRouter STT sends JSON base64 audio and returns transcript" do
    openrouter = configure_openrouter_speech_provider!(stt_model: "openai/whisper-1")
    captured = {}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v1/audio/transcriptions") do |env|
        captured[:authorization] = env.request_headers["Authorization"]
        captured[:content_type] = env.request_headers["Content-Type"]
        captured[:body] = JSON.parse(env.body)
        [ 200, { "Content-Type" => "application/json" }, { text: "Hello from OpenRouter" }.to_json ]
      end
    end
    conn = faraday_test_conn(openrouter.api_base_uri, stubs)

    with_default_speech_conn(conn) do
      AudioConverter.stub(:convert_to_base64_wav, "BASE64WAV") do
        service = SpeechService.new(current_user: @user, conversation: @conversation)
        Tempfile.create([ "audio", ".wav" ]) do |file|
          file.write("abc")
          file.rewind
          assert_equal "Hello from OpenRouter", service.transcribe(file)
        end
      end
    end

    assert_equal "Bearer openrouter-test-token", captured[:authorization]
    assert_equal "application/json", captured[:content_type]
    assert_equal "openai/whisper-1", captured.dig(:body, "model")
    assert_equal({ "data" => "BASE64WAV", "format" => "wav" }, captured.dig(:body, "input_audio"))
    stubs.verify_stubbed_calls
  end

  test "OpenRouter STT raises on blank transcription response" do
    openrouter = configure_openrouter_speech_provider!(stt_model: "openai/whisper-1")
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v1/audio/transcriptions") do |_env|
        [ 200, { "Content-Type" => "application/json" }, {}.to_json ]
      end
    end
    conn = faraday_test_conn(openrouter.api_base_uri, stubs)

    with_default_speech_conn(conn) do
      AudioConverter.stub(:convert_to_base64_wav, "BASE64WAV") do
        service = SpeechService.new(current_user: @user, conversation: @conversation)
        Tempfile.create([ "audio", ".wav" ]) do |file|
          file.write("abc")
          file.rewind
          error = assert_raises(SpeechService::SpeechServiceError) { service.transcribe(file) }
          assert_match(/empty transcription/i, error.message)
        end
      end
    end

    stubs.verify_stubbed_calls
  end

  test "OpenRouter TTS requests PCM and streams webm audio" do
    openrouter = configure_openrouter_speech_provider!(
      tts_model: "mistralai/voxtral-mini-tts-2603",
      tts_voice: "alloy"
    )
    captured_formats = []
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v1/audio/speech") do |env|
        body = JSON.parse(env.body)
        captured_formats << body["response_format"]
        [ 200, { "Content-Type" => "audio/pcm" }, ("\x00\x00".b * 24_000) ]
      end
    end
    conn = faraday_test_conn(openrouter.api_base_uri, stubs)

    service = SpeechService.new(current_user: @user, conversation: @conversation)
    chunks = []
    service.tts_stream("hello world", connection: conn) { |chunk| chunks << chunk }

    assert_equal [ "pcm" ], captured_formats
    assert_operator chunks.join.bytesize, :>, 0
    stubs.verify_stubbed_calls
  end

  test "OpenRouter TTS falls back to mp3 when PCM fails before streaming" do
    openrouter = configure_openrouter_speech_provider!(
      tts_model: "mistralai/voxtral-mini-tts-2603",
      tts_voice: "alloy"
    )
    captured_formats = []
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/api/v1/audio/speech") do |env|
        body = JSON.parse(env.body)
        captured_formats << body["response_format"]
        if body["response_format"] == "pcm"
          [ 500, { "Content-Type" => "application/json" }, "" ]
        else
          [ 200, { "Content-Type" => "audio/mpeg" }, File.binread(Rails.root.join("test/fixtures/files/sample.ogg")) ]
        end
      end
    end
    conn = faraday_test_conn(openrouter.api_base_uri, stubs)

    service = SpeechService.new(current_user: @user, conversation: @conversation)
    chunks = []
    service.tts_stream("hello world", connection: conn) { |chunk| chunks << chunk }

    assert_equal [ "pcm", "mp3" ], captured_formats
    assert_operator chunks.join.bytesize, :>, 0
    stubs.verify_stubbed_calls
  end

  test "OpenRouter TTS ignores streamed PCM error bodies before falling back to mp3" do
    configure_openrouter_speech_provider!(
      tts_model: "mistralai/voxtral-mini-tts-2603",
      tts_voice: "alloy"
    )
    conn = StreamingTtsFallbackConnection.new(
      fallback_audio: File.binread(Rails.root.join("test/fixtures/files/sample.ogg"))
    )

    service = SpeechService.new(current_user: @user, conversation: @conversation)
    chunks = []
    service.tts_stream("hello world", connection: conn) { |chunk| chunks << chunk }

    assert_equal [ "pcm", "mp3" ], conn.requested_formats
    assert_operator chunks.join.bytesize, :>, 0
  end

  private

  class StreamingTtsFallbackConnection
    Response = Struct.new(:status, :body) do
      def success?
        status.between?(200, 299)
      end
    end

    Request = Struct.new(:headers, :body, :options)

    attr_reader :requested_formats

    def initialize(fallback_audio:)
      @fallback_audio = fallback_audio
      @requested_formats = []
    end

    def post(_path)
      request = Request.new({}, nil, Faraday::RequestOptions.new)
      yield request
      format = JSON.parse(request.body).fetch("response_format")
      requested_formats << format

      if format == "pcm"
        env = Faraday::Env.from(status: 500, response_headers: { "Content-Type" => "application/json" })
        request.options.on_data.call('{"error":{"message":"PCM unavailable"}}', 39, env)
        raise Faraday::ServerError.new("the server responded with status 500", status: 500, body: "")
      end

      env = Faraday::Env.from(status: 200, response_headers: { "Content-Type" => "audio/mpeg" })
      request.options.on_data.call(@fallback_audio, @fallback_audio.bytesize, env)
      Response.new(200, "")
    end
  end

  def configure_openrouter_speech_provider!(stt_model: "openai/whisper-1", tts_model: "openai/gpt-4o-mini-tts", tts_voice: "alloy")
    openrouter = SupportedApi.find_or_create_by!(api_base_uri: SupportedApi::OPENROUTER_BASE_URI) do |api|
      api.api_access_token = "openrouter-test-token"
      api.enabled = true
    end
    openrouter.update!(api_access_token: "openrouter-test-token", enabled: true)
    AppSetting.settings.update!(
      provider_supported_api_id: openrouter.id,
      stt_method: "speech",
      stt_model: stt_model,
      tts_model: tts_model,
      tts_voice: tts_voice
    )
    openrouter
  end

  def faraday_test_conn(url, stubs)
    Faraday.new(url: url) do |builder|
      builder.request :authorization, "Bearer", "openrouter-test-token"
      builder.response :raise_error
      builder.adapter :test, stubs
    end
  end

  def with_default_speech_conn(conn)
    original = SpeechService.default_conn
    SpeechService.default_conn = conn
    yield
  ensure
    SpeechService.default_conn = original
  end

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
