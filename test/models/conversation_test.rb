require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  def setup
    @conversation = conversations(:student_generic_conversation)
  end

  test "audio_input_permitted? is false when llm does not support audio" do
    # Ensure llm for this conversation reports no audio support
    llm = Llm.create!(model: "no-audio", api_provider: "https://api.example.com/", supports_audio_input: false)
    # Force the conversation to use this LLM instance to avoid matching issues via settings lookup.
    @conversation.define_singleton_method(:llm_in_use) { llm }
    user = @conversation.user
    user.setting.update!(llm_model_name: llm.model, llm_api_base_uri: llm.api_provider)
    assert_not @conversation.audio_input_permitted?
  end

  test "audio_input_permitted? is true when llm supports audio and audio setting enabled" do
    llm = Llm.create!(model: "audio-model", api_provider: "https://api.example.com/", supports_audio_input: true)
    # Force the conversation to use this LLM instance to avoid matching issues via settings lookup.
    @conversation.define_singleton_method(:llm_in_use) { llm }
    user = @conversation.user
    user.setting.update!(llm_model_name: llm.model, llm_api_base_uri: llm.api_provider)
    assert @conversation.audio_input_permitted?
  end

  test "auto_read_default returns true only when audio_setting is 'only' and speech configured" do
    # Create an LLM that supports audio and set user to use it
    llm = Llm.create!(model: "audio-only", api_provider: "https://api.example.com/", supports_audio_input: true)
    user = @conversation.user
    user.setting.update!(llm_model_name: llm.model, llm_api_base_uri: llm.api_provider)

    # Ensure AppSetting is configured for speech
    app = AppSetting.first
    app.update!(stt_method: "speech", stt_model: "transcribe-1", provider_supported_api_id: supported_apis(:example_api).id)

    # Force lesson-less conversation (generic) to return "only" via audio_setting override
    # Stub lesson_progress to be nil and audio_input_supported to true
    Conversation.stub(:find, ->(id) { @conversation }) do
      @conversation.define_singleton_method(:audio_setting) { "only" }
      assert @conversation.auto_read_default
    end
  end
end
