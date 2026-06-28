require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  def setup
    @conversation = conversations(:student_generic_conversation)
  end

  test "context_usage uses last prompt tokens and selected llm context length" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 77")
    llm = Llm.create!(model: "context-model", api_provider: "https://api.context.test/", context_length: 200_000)
    Completion.create!(
      model: llm.model,
      api_provider: llm.api_provider,
      prompt_tokens: 50_000,
      llm: llm,
      conversation: conversation
    )

    conversation.user.setting.update!(
      llm_model_name: llm.model,
      llm_api_base_uri: llm.api_provider
    )

    assert_in_delta 25.0, conversation.context_usage, 0.0001
  end

  test "llm_in_use falls back to ENV defaults when user settings are blank" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 78")
    conversation.user.setting.update!(llm_model_name: nil, llm_api_base_uri: nil)

    ENV["DEFAULT_MODEL"] = "env-model"
    ENV["OPENAI_API_BASE_URL"] = "https://env.example.com/"
    llm = Llm.create!(model: "env-model", api_provider: "https://env.example.com/")

    assert_equal llm, conversation.llm_in_use
  ensure
    ENV.delete("DEFAULT_MODEL")
    ENV.delete("OPENAI_API_BASE_URL")
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

  test "auto_read_default returns true only when audio_setting is 'only' and TTS configured" do
    # Create an LLM that supports audio and set user to use it
    llm = Llm.create!(model: "audio-only", api_provider: "https://api.example.com/", supports_audio_input: true)
    user = @conversation.user
    user.setting.update!(llm_model_name: llm.model, llm_api_base_uri: llm.api_provider)

    # Ensure AppSetting is configured for TTS
    app = AppSetting.first
    app.update!(
      stt_method: "speech",
      stt_model: "transcribe-1",
      provider_supported_api_id: supported_apis(:example_api).id,
      tts_model: "tts-1",
      tts_voice: "alloy"
    )

    # Force lesson-less conversation (generic) to return "only" via audio_setting override
    # Stub lesson_progress to be nil and audio_input_supported to true
    Conversation.stub(:find, ->(id) { @conversation }) do
      @conversation.define_singleton_method(:audio_setting) { "only" }
      assert @conversation.auto_read_default

      app.update!(tts_model: nil)
      refute @conversation.auto_read_default
    end
  end

  test "clear! removes messages and resets responses state" do
    @conversation.messages.delete_all
    @conversation.update!(
      responses_previous_id: "resp_123",
      responses_provider: "https://openrouter.ai/api/v1/",
      responses_model: "gpt-test"
    )
    @conversation.messages.create!(role: :user, content: "Hello")
    @conversation.messages.create!(role: :assistant, content: "Hi")

    @conversation.clear!

    @conversation.reload
    assert_empty @conversation.messages
    assert_nil @conversation.responses_previous_id
    assert_nil @conversation.responses_provider
    assert_nil @conversation.responses_model
  end
end
