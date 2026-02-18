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
