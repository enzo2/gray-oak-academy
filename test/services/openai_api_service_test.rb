require "test_helper"
require "ostruct"
require "bigdecimal"

class OpenaiApiServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @messages = [ { role: "user", content: "Hello" } ]
    @base_uri = "https://api.test/"
    @access_token = "tok"
    @model = "m1"
  end

  test "complete injects system prompt when missing and returns content" do
    fake_client = build_chat_client do |_params|
      { "choices" => [ { "message" => { "content" => "LLM reply" } } ], "usage" => { "prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2 } }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      result = service.complete(@messages, temperature: 0.5)
      assert_equal "LLM reply", result
    end
  end

  test "complete accepts string keyed messages and does not mutate caller array" do
    captured = nil
    input_messages = [ { "role" => "user", "content" => "Hello" } ]
    original = Marshal.load(Marshal.dump(input_messages))
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "ok" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      result = service.complete(input_messages)
      assert_equal "ok", result
    end

    assert_equal original, input_messages
    assert_equal "system", captured[:messages].first[:role]
  end

  test "complete preserves tool call metadata as provided" do
    captured = nil
    input_messages = [
      {
        "role" => "assistant",
        "tool_calls" => [
          {
            "id" => "call_1",
            "type" => "function",
            "extra_content" => { "google" => { "thought_signature" => "sig_1" } },
            "function" => { "name" => "Generate_Lesson_Plan", "arguments" => "{}" }
          }
        ]
      },
      { "role" => "tool", "tool_call_id" => "call_1", "content" => "ok" },
      { "role" => "user", "content" => "Continue." }
    ]
    original = Marshal.load(Marshal.dump(input_messages))

    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "ok" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://openrouter.ai/api/v1/",
        model: "google/gemini-2.5-pro"
      )
      result = service.complete(input_messages)
      assert_equal "ok", result
    end

    assistant_message = captured[:messages].find do |message|
      role = message[:role] || message["role"]
      tool_calls = message[:tool_calls] || message["tool_calls"]
      role.to_s == "assistant" && tool_calls.present?
    end
    tool_call = (assistant_message[:tool_calls] || assistant_message["tool_calls"]).first

    assert_equal "sig_1", tool_call.dig("extra_content", "google", "thought_signature")
    assert_equal original, input_messages
  end

  test "complete preserves existing system prompt" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "ok" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      messages = [ { role: "system", content: "custom system" }, { role: "user", content: "Hello" } ]
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      service.complete(messages)
      assert_equal "custom system", captured[:messages].first[:content]
      assert_equal 1, captured[:messages].count { |m| m[:role] == "system" }
    end
  end

  test "complete appends prefill for non-openai base and restores response" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "world" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: "https://openrouter.ai/api/v1/", model: @model)
      result = service.complete(@messages, prefill: "Hello ")
      assert_equal "Hello world", result
      assert_equal "assistant", captured[:messages].last[:role]
      assert_equal "Hello ", captured[:messages].last[:content]
    end
  end

  test "complete does not append prefill for OpenAI base" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "world" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: "https://api.openai.com/v1/", model: @model)
      result = service.complete(@messages, prefill: "Hello ")
      assert_equal "world", result
      assert_equal "user", captured[:messages].last[:role]
    end
  end

  test "complete does not append prefill for xAI base" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "world" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: "https://api.x.ai/v1/", model: @model)
      result = service.complete(@messages, prefill: "Hello ")
      assert_equal "world", result
      assert_equal "user", captured[:messages].last[:role]
      assert_equal "Hello", captured[:messages].last[:content]
    end
  end

  test "complete sets low reasoning effort for OpenAI chat calls" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "ok" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model
      )
      service.complete(@messages)
    end

    assert_equal "low", captured[:reasoning_effort]
    assert_nil captured[:reasoning]
  end

  test "complete sets high reasoning effort for OpenAI reasoning-model calls" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "ok" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        reasoning_model: true
      )
      service.complete(@messages)
    end

    assert_equal "high", captured[:reasoning_effort]
    assert_nil captured[:reasoning]
  end

  test "complete sets high effort and visible reasoning for OpenRouter reasoning-model calls" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "ok" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://openrouter.ai/api/v1/",
        model: @model,
        reasoning_model: true
      )
      service.complete(@messages)
    end

    assert_equal({ effort: "high", exclude: false }, captured[:reasoning])
    assert_nil captured[:reasoning_effort]
  end

  test "complete omits reasoning effort for xAI reasoning-model calls" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "ok" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.x.ai/v1/",
        model: @model,
        reasoning_model: true
      )
      service.complete(@messages)
    end

    assert_nil captured[:reasoning_effort]
    assert_nil captured[:reasoning]
  end

  test "complete uses standard reasoning_effort for unknown providers" do
    captured = nil
    fake_client = build_chat_client do |params|
      captured = params
      { "choices" => [ { "message" => { "content" => "ok" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        reasoning_model: true
      )
      service.complete(@messages)
    end

    assert_equal "high", captured[:reasoning_effort]
    assert_nil captured[:reasoning]
  end

  test "complete raises OpenAiError on OpenAI::Errors::APITimeoutError" do
    fake_client = build_chat_client do |_params|
      raise OpenAI::Errors::APITimeoutError.new("timeout")
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      assert_raises(OpenAiError) { service.complete(@messages) }
    end
  end

  test "complete raises OpenAiError on OpenAI::Errors::BadRequestError with error message" do
    fake_client = build_chat_client do |_params|
      raise OpenAI::Errors::BadRequestError.new(
        url: "https://api.test/chat",
        status: 400,
        headers: {},
        body: { error: { message: "Bad request error" } }.to_json,
        request: nil,
        response: nil,
        message: "bad request"
      )
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages) }
      assert_includes exception.message, "Bad request error"
    end
  end

  test "complete raises OpenAiError on OpenAI::Errors::AuthenticationError" do
    fake_client = build_chat_client do |_params|
      raise OpenAI::Errors::AuthenticationError.new(
        url: "https://api.test/chat",
        status: 401,
        headers: {},
        body: { error: { message: "Unauthorized" } }.to_json,
        request: nil,
        response: nil,
        message: "unauthorized"
      )
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages) }
      assert_includes exception.message.downcase, "access key was unauthorized"
    end
  end

  test "complete raises OpenAiError on empty response" do
    fake_client = build_chat_client do |_params|
      { "choices" => [ { "message" => { "content" => "" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages) }
      assert_equal "Empty response from LLM.", exception.message
    end
  end

  test "complete raises OpenAiError on refusal" do
    fake_client = build_chat_client do |_params|
      { "choices" => [ { "message" => { "refusal" => "I cannot fulfill this request." } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages) }
      assert_equal "Response refused with message: I cannot fulfill this request.", exception.message
    end
  end

  test "complete returns image message when image generation is enabled" do
    fake_client = build_chat_client do |_params|
      {
        "choices" => [
          { "message" => { "content" => "", "images" => [ { "b64_json" => "img" } ] } }
        ]
      }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://openrouter.ai/api/v1/",
        model: @model,
        image_generation: true
      )
      result = service.complete(@messages)
      assert_equal [ { "b64_json" => "img" } ], result["images"]
    end
  end

  test "complete streams and logs usage when stream handler is provided" do
    chunks = [
      { "choices" => [ { "delta" => { "content" => "Hi" } } ] },
      { "choices" => [ { "finish_reason" => "stop" } ], "model" => "m-stream" },
      { "usage" => { "prompt_tokens" => 1, "completion_tokens" => 2, "total_tokens" => 3 } }
    ]

    fake_client = build_streaming_chat_client(chunks: chunks)
    received = []
    handler = ->(choice) { received << choice }
    created = nil

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      Completion.stub(:create, ->(attrs) { created = attrs }) do
        service = OpenaiApiService.new(
          current_user: @user,
          access_token: @access_token,
          base_uri: @base_uri,
          model: @model,
          stream_handler: handler
        )
        service.complete(@messages)
      end
    end

    assert_equal 2, received.length
    assert_equal "Hi", received.first.dig("delta", "content")
    assert_equal "m-stream", created[:model]
    assert_equal 1, created[:prompt_tokens]
    assert_equal 2, created[:completion_tokens]
    assert_equal 3, created[:total_tokens]
  end

  test "complete parses and validates JSON response" do
    schema = {
      "type" => "object",
      "properties" => {
        "name" => { "type" => "string" }
      },
      "required" => [ "name" ]
    }
    fake_client = build_chat_client do |_params|
      { "choices" => [ { "message" => { "content" => '{"name": "Test"}' } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      result = service.complete(@messages, response_format: { type: "json_object" }, schema: schema)
      assert_equal({ "name" => "Test" }, result)
    end
  end

  test "complete raises OpenAiError for invalid JSON response" do
    schema = {
      "type" => "object",
      "properties" => {
        "name" => { "type" => "string" }
      },
      "required" => [ "name" ]
    }
    fake_client = build_chat_client do |_params|
      { "choices" => [ { "message" => { "content" => '{"invalid": "json"}' } } ] }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages, response_format: { type: "json_object" }, schema: schema) }
      assert_includes exception.message, "Invalid JSON structure"
    end
  end

  test "complete repairs and validates malformed JSON response" do
    schema = {
      "type" => "object",
      "properties" => {
        "name" => { "type" => "string" }
      },
      "required" => [ "name" ]
    }
    fake_client = build_chat_client do |_params|
      { "choices" => [ { "message" => { "content" => '{"name": "Test",}' } } ] } # Malformed JSON
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      result = service.complete(@messages, response_format: { type: "json_object" }, schema: schema)
      assert_equal({ "name" => "Test" }, result)
    end
  end

  test "complete extracts valid JSON object when content contains earlier invalid brace blocks" do
    schema = {
      "type" => "object",
      "properties" => {
        "name" => { "type" => "string" }
      },
      "required" => [ "name" ]
    }
    fake_client = build_chat_client do |_params|
      {
        "choices" => [
          { "message" => { "content" => "Assistant notes: {not valid json} Final output: {\"name\":\"Test\"}" } }
        ]
      }
    end

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: "https://api.x.ai/v1/", model: @model)
      result = service.complete(@messages, response_format: { type: "json_object" }, schema: schema, prefill: "{\"name\":")
      assert_equal({ "name" => "Test" }, result)
    end
  end

  # New tests for determine_tools behavior

  test "determine_tools limits to student tools for lesson conversations" do
    tool_struct = Struct.new(:access, :name) do
      def for_llm
        { "function" => { "name" => name } }
      end
    end

    admin_tool = tool_struct.new("admin", "List_Students")
    student_tool = tool_struct.new("student", "Show_On_Chalkboard")
    allowed_tools = [ admin_tool, student_tool ]
    # Provide a simple where implementation to mimic ActiveRecord::Relation#where
    def allowed_tools.where(hash)
      select { |t| t.access.to_s == hash[:access].to_s }
    end

    Tool.stub(:enabled_for_user, ->(user) { allowed_tools }) do
      conversation = OpenStruct.new(lesson_progress: Object.new)
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: @base_uri,
        model: @model,
        conversation: conversation,
        enable_tools: true
      )

      tool_names = service.instance_variable_get(:@tools).map { |t| t.dig("function", "name") }
      assert_equal [ "Show_On_Chalkboard" ], tool_names
    end
  end

  test "determine_tools keeps Generate_Image regardless of current provider base_uri" do
    tool_struct = Struct.new(:access, :name) do
      def for_llm
        { "function" => { "name" => name } }
      end
    end

    gen_tool = tool_struct.new("student", "Generate_Image")
    student_tool = tool_struct.new("student", "Show_On_Chalkboard")
    allowed_tools = [ gen_tool, student_tool ]
    def allowed_tools.where(hash)
      select { |t| t.access.to_s == hash[:access].to_s }
    end

    Tool.stub(:enabled_for_user, ->(user) { allowed_tools }) do
      conversation = OpenStruct.new(lesson_progress: nil)
      # Use a non-OpenRouter base_uri; tool availability should not depend on active chat provider.
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        conversation: conversation,
        enable_tools: true
      )

      tool_names = service.instance_variable_get(:@tools).map { |t| t.dig("function", "name") }
      assert_equal [ "Generate_Image", "Show_On_Chalkboard" ], tool_names
    end
  end

  test "check_cost_limits blocks over daily budget for non-lesson chat" do
    service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)

    AppSetting.stub(:settings, OpenStruct.new(max_chat_cost: nil)) do
      @user.stub(:daily_budget, BigDecimal("1.00")) do
        stub_completion_sums(daily_sum: BigDecimal("1.10")) do
          service.stub(:notify_admins_of_limit, nil) do
            assert_raises(OpenAiError) { service.send(:check_cost_limits) }
          end
        end
      end
    end
  end

  test "check_cost_limits allows active lesson up to 25 percent over budget" do
    conversation = OpenStruct.new(lesson_progress: OpenStruct.new(completed?: false))
    service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model, conversation: conversation)

    AppSetting.stub(:settings, OpenStruct.new(max_chat_cost: nil)) do
      @user.stub(:daily_budget, BigDecimal("1.00")) do
        stub_completion_sums(daily_sum: BigDecimal("1.20")) do
          service.stub(:notify_admins_of_limit, nil) do
            assert_nothing_raised { service.send(:check_cost_limits) }
          end
        end
      end
    end
  end

  test "check_cost_limits blocks active lesson beyond allowance" do
    conversation = OpenStruct.new(lesson_progress: OpenStruct.new(completed?: false))
    service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model, conversation: conversation)

    AppSetting.stub(:settings, OpenStruct.new(max_chat_cost: nil)) do
      @user.stub(:daily_budget, BigDecimal("1.00")) do
        stub_completion_sums(daily_sum: BigDecimal("1.30")) do
          service.stub(:notify_admins_of_limit, nil) do
            assert_raises(OpenAiError) { service.send(:check_cost_limits) }
          end
        end
      end
    end
  end

  test "check_cost_limits blocks completed lesson once budget exceeded" do
    conversation = OpenStruct.new(lesson_progress: OpenStruct.new(completed?: true))
    service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model, conversation: conversation)

    AppSetting.stub(:settings, OpenStruct.new(max_chat_cost: nil)) do
      @user.stub(:daily_budget, BigDecimal("1.00")) do
        stub_completion_sums(daily_sum: BigDecimal("1.10")) do
          service.stub(:notify_admins_of_limit, nil) do
            assert_raises(OpenAiError) { service.send(:check_cost_limits) }
          end
        end
      end
    end
  end

  test "initialize raises when api overrides are incomplete" do
    assert_raises(OpenAiError) do
      OpenaiApiService.new(current_user: @user, base_uri: @base_uri)
    end
  end

  test "initialize raises for orphaned student accounts" do
    orphaned_student = users(:student2)
    assert_raises(OpenAiError) do
      OpenaiApiService.new(current_user: orphaned_student, access_token: @access_token, base_uri: @base_uri, model: @model)
    end
  end

  test "list_models returns model ids" do
    fake_page = OpenStruct.new(
      data: [
        OpenStruct.new(id: "m1"),
        OpenStruct.new(id: "m2")
      ]
    )
    fake_models = Object.new
    def fake_models.list
      @page
    end
    fake_models.instance_variable_set(:@page, fake_page)
    fake_client = Object.new
    def fake_client.models
      @models
    end
    fake_client.instance_variable_set(:@models, fake_models)

    OpenAI::Client.stub(:new, ->(**_kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      assert_equal [ "m1", "m2" ], service.list_models
    end
  end

  private

  def build_chat_client(&create_proc)
    completions = Object.new
    completions.define_singleton_method(:create) do |**params|
      create_proc.call(params)
    end

    chat = Object.new
    chat.define_singleton_method(:completions) { completions }

    client = Object.new
    client.define_singleton_method(:chat) { chat }

    client
  end

  def build_streaming_chat_client(chunks:)
    completions = Object.new
    completions.define_singleton_method(:stream_raw) do |**_params|
      chunks.each
    end

    chat = Object.new
    chat.define_singleton_method(:completions) { completions }

    client = Object.new
    client.define_singleton_method(:chat) { chat }

    client
  end

  def stub_completion_sums(daily_sum:, chat_sum: BigDecimal("0"), &block)
    daily_relation = Class.new do
      def initialize(sum)
        @sum = sum
      end

      def in_date_range(*)
        self
      end

      def sum(_)
        @sum
      end
    end.new(daily_sum)

    conversation_relation = Class.new do
      def initialize(sum)
        @sum = sum
      end

      def sum(_)
        @sum
      end
    end.new(chat_sum)

    Completion.stub(:where, ->(query) { query.key?(:user) ? daily_relation : conversation_relation }, &block)
  end
end
