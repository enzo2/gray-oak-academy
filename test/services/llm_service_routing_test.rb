require "test_helper"

class LlmServiceRoutingTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @model = "m1"
    @access_token = "tok"
    @fake_sdk_client = Object.new
  end

  test "completion job class routes responses hosts to responses job" do
    assert_equal GetResponsesCompletionJob,
                 LlmServiceRouting.completion_job_class_for(
                   user: @user,
                   base_uri: SupportedApi::OPENAI_CODEX_BASE_URI
                 )
  end

  test "completion job class routes unsupported hosts to chat completions job" do
    assert_equal GetLlmCompletionJob,
                 LlmServiceRouting.completion_job_class_for(
                   user: @user,
                   base_uri: "https://api.compatible.local/v1/"
                 )
  end

  test "build_completion_client returns responses service for responses hosts" do
    OpenAI::Client.stub(:new, ->(**_kwargs) { @fake_sdk_client }) do
      client = LlmServiceRouting.build_completion_client(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        log_completion: false
      )

      assert_instance_of OpenaiResponsesService, client
    end
  end

  test "build_completion_client returns chat completions service for compatible hosts" do
    OpenAI::Client.stub(:new, ->(**_kwargs) { @fake_sdk_client }) do
      client = LlmServiceRouting.build_completion_client(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.compatible.local/v1/",
        model: @model,
        log_completion: false
      )

      assert_instance_of OpenaiApiService, client
    end
  end

  test "complete_structured_output includes prefill for chat completions clients only" do
    captured = {}
    chat_client = OpenaiApiService.allocate
    chat_client.define_singleton_method(:complete) do |messages, **kwargs|
      captured[:chat] = kwargs
      { "ok" => true }
    end

    responses_client = OpenaiResponsesService.allocate
    responses_client.define_singleton_method(:complete) do |messages, **kwargs|
      captured[:responses] = kwargs
      { "ok" => true }
    end

    LlmServiceRouting.complete_structured_output(
      client: chat_client,
      messages: [ { role: "user", content: "hello" } ],
      response_format: { type: "json_schema" },
      schema: { "type" => "object" },
      prefill: "{"
    )

    LlmServiceRouting.complete_structured_output(
      client: responses_client,
      messages: [ { role: "user", content: "hello" } ],
      response_format: { type: "json_schema" },
      schema: { "type" => "object" },
      prefill: "{"
    )

    assert_equal "{", captured[:chat][:prefill]
    refute_includes captured[:responses].keys, :prefill
  end
end
