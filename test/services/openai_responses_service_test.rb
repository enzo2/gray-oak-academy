require "test_helper"

class OpenaiResponsesServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @conversation = conversations(:teacher_generic_conversation)
    @base_uri = "https://api.test/"
    @access_token = "tok"
    @model = "m1"
  end

  test "complete converts string keyed tool call history into Responses input items" do
    captured = nil
    messages = [
      { "role" => "system", "content" => "Custom system prompt" },
      { "role" => "user", "content" => "Find answer" },
      {
        "role" => "assistant",
        "content" => nil,
        "tool_calls" => [
          { "id" => "call_1", "function" => { "name" => "Lookup", "arguments" => "{\"query\":\"x\"}" } }
        ]
      },
      { "role" => "tool", "tool_call_id" => "call_1", "content" => "tool output" }
    ]

    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete(messages)
      assert_equal "Done", result
    end

    assert_equal "Custom system prompt", captured[:instructions]
    assert_equal "user", captured[:input][0]["role"]
    assert_equal "Find answer", captured[:input][0]["content"]
    assert_equal "function_call", captured[:input][1]["type"]
    assert_equal "call_1", captured[:input][1]["call_id"]
    assert_equal "Lookup", captured[:input][1]["name"]
    assert_equal "function_call_output", captured[:input][2]["type"]
    assert_equal "call_1", captured[:input][2]["call_id"]
    assert_equal "tool output", captured[:input][2]["output"]
  end

  test "complete with store false does not write response state to conversation" do
    @conversation.update!(
      responses_previous_id: "resp_prev",
      responses_provider: @base_uri,
      responses_model: @model
    )

    captured = nil
    fake_client = build_responses_client do |params|
      captured = params
      response_payload("Done", id: "resp_new")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        conversation: @conversation,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      service.complete([ { role: "user", content: "Hello" } ], store: false)
    end

    assert_equal false, captured[:store]
    assert_nil captured[:previous_response_id]

    @conversation.reload
    assert_equal "resp_prev", @conversation.responses_previous_id
    assert_equal @base_uri, @conversation.responses_provider
    assert_equal @model, @conversation.responses_model
  end

  test "complete does not raise on tool-call-only output without text" do
    fake_client = build_responses_client do |_params|
      {
        "id" => "resp_tool_only",
        "model" => @model,
        "output" => [
          { "type" => "function_call", "call_id" => "call_1", "name" => "Lookup", "arguments" => "{}" }
        ],
        "usage" => {}
      }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete([ { role: "user", content: "Find answer" } ])
      assert_equal "", result
      assert_equal "resp_tool_only", service.last_response_id
    end
  end

  test "complete parses string keyed response_format for structured outputs" do
    fake_client = build_responses_client do |_params|
      response_payload("{\"name\":\"Ada\"}")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiResponsesService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        log_completion: false
      )

      result = service.complete(
        [ { role: "user", content: "Return JSON" } ],
        response_format: { "type" => "json_object" }
      )
      assert_equal({ "name" => "Ada" }, result)
    end
  end

  private

  def build_responses_client(&create_proc)
    responses = Object.new
    responses.define_singleton_method(:create) do |**params|
      create_proc.call(params)
    end

    client = Object.new
    client.define_singleton_method(:responses) { responses }
    client
  end

  def response_payload(text, id: "resp_1")
    {
      "id" => id,
      "model" => @model,
      "output" => [
        {
          "type" => "message",
          "content" => [
            { "type" => "output_text", "text" => text }
          ]
        }
      ],
      "usage" => {}
    }
  end
end
