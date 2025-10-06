require "test_helper"
require "ostruct"

class OpenaiApiServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:admin)
    @messages = [ { role: "user", content: "Hello" } ]
    @base_uri = "https://api.test/"
    @access_token = "tok"
    @model = "m1"
  end

  test "complete injects system prompt when missing and returns content" do
    fake_client = Object.new
    def fake_client.chat(parameters:)
      { "choices" => [ { "message" => { "content" => "LLM reply" } } ], "usage" => { "prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2 } }
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      result = service.complete(@messages, temperature: 0.5)
      assert_equal "LLM reply", result
    end
  end

  test "complete raises OpenAiError on Faraday::TimeoutError" do
    fake_client = Object.new
    def fake_client.chat(parameters:)
      raise Faraday::TimeoutError.new("timeout")
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      assert_raises(OpenAiError) { service.complete(@messages) }
    end
  end

  test "complete raises OpenAiError on Faraday::BadRequestError with error message" do
    fake_client = Object.new
    def fake_client.chat(parameters:)
      response_env = { status: 400, body: { error: { message: "Bad request error" } }.to_json }
      raise Faraday::BadRequestError.new("bad request", response_env)
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages) }
      assert_includes exception.message, "Bad request error"
    end
  end

  test "complete raises OpenAiError on Faraday::UnauthorizedError" do
    fake_client = Object.new
    def fake_client.chat(parameters:)
      response_env = { status: 401, body: { error: { message: "Unauthorized" } }.to_json }
      raise Faraday::UnauthorizedError.new("unauthorized", response_env)
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages) }
      assert_includes exception.message.downcase, "access key was unauthorized"
    end
  end

  test "complete raises OpenAiError on empty response" do
    fake_client = Object.new
    def fake_client.chat(parameters:)
      { "choices" => [ { "message" => { "content" => "" } } ] }
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages) }
      assert_equal "Empty response from LLM.", exception.message
    end
  end

  test "complete raises OpenAiError on refusal" do
    fake_client = Object.new
    def fake_client.chat(parameters:)
      { "choices" => [ { "message" => { "refusal" => "I cannot fulfill this request." } } ] }
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      exception = assert_raises(OpenAiError) { service.complete(@messages) }
      assert_equal "Response refused with message: I cannot fulfill this request.", exception.message
    end
  end

  test "complete parses and validates JSON response" do
    schema = {
      "type" => "object",
      "properties" => {
        "name" => { "type" => "string" }
      },
      "required" => [ "name" ]
    }
    fake_client = Object.new
    def fake_client.chat(parameters:)
      { "choices" => [ { "message" => { "content" => '{"name": "Test"}' } } ] }
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
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
    fake_client = Object.new
    def fake_client.chat(parameters:)
      { "choices" => [ { "message" => { "content" => '{"invalid": "json"}' } } ] }
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
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
    fake_client = Object.new
    def fake_client.chat(parameters:)
      { "choices" => [ { "message" => { "content" => '{"name": "Test",}' } } ] } # Malformed JSON
    end

    OpenAI::Client.stub(:new, ->(**kwargs) { fake_client }) do
      service = OpenaiApiService.new(current_user: @user, access_token: @access_token, base_uri: @base_uri, model: @model)
      result = service.complete(@messages, response_format: { type: "json_object" }, schema: schema)
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
    student_tool = tool_struct.new("student", "Chalkboard_URL")
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
      assert_equal [ "Chalkboard_URL" ], tool_names
    end
  end

  test "determine_tools filters Generate_Image unless provider is OpenRouter" do
    tool_struct = Struct.new(:access, :name) do
      def for_llm
        { "function" => { "name" => name } }
      end
    end

    gen_tool = tool_struct.new("student", "Generate_Image")
    student_tool = tool_struct.new("student", "Chalkboard_URL")
    allowed_tools = [ gen_tool, student_tool ]
    def allowed_tools.where(hash)
      select { |t| t.access.to_s == hash[:access].to_s }
    end

    Tool.stub(:enabled_for_user, ->(user) { allowed_tools }) do
      conversation = OpenStruct.new(lesson_progress: nil)
      # Use a base_uri that does NOT include openrouter.ai so Generate_Image will be filtered
      service = OpenaiApiService.new(
        current_user: @user,
        access_token: @access_token,
        base_uri: "https://api.openai.com/v1/",
        model: @model,
        conversation: conversation,
        enable_tools: true
      )

      tool_names = service.instance_variable_get(:@tools).map { |t| t.dig("function", "name") }
      assert_equal [ "Chalkboard_URL" ], tool_names
    end
  end
end
