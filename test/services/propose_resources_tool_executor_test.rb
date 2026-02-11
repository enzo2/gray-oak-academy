require "test_helper"

class ProposeResourcesToolExecutorTest < ActiveSupport::TestCase
  def build_executor(exa_service: Object.new)
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    executor = nil

    ExaApiService.stub(:new, ->(**_kwargs) { exa_service }) do
      executor = ProposeResourcesToolExecutor.new(lesson_plan: lesson_plan, current_user: teacher)
    end
    executor
  end

  test "strict tool schemas require every property key" do
    executor = build_executor()

    executor.tool_definitions.each do |tool|
      next unless tool[:strict]

      properties = tool.dig(:parameters, :properties)&.keys&.map(&:to_s) || []
      required = tool.dig(:parameters, :required)&.map(&:to_s) || []
      assert_equal properties.sort, required.sort, "#{tool[:name]} strict schema required list must match properties keys"
    end
  end

  test "validate_public_https_url rejects loopback IPv4 literals" do
    executor = build_executor()

    error = assert_raises(ProposeResourcesToolExecutor::ToolExecutionError) do
      executor.send(:validate_public_https_url!, "https://127.0.0.1/private")
    end
    assert_includes error.message, "private or reserved IP"
  end

  test "validate_public_https_url rejects IPv4-mapped loopback IPv6 literals" do
    executor = build_executor()

    error = assert_raises(ProposeResourcesToolExecutor::ToolExecutionError) do
      executor.send(:validate_public_https_url!, "https://[::ffff:127.0.0.1]/private")
    end
    assert_includes error.message, "private or reserved IP"
  end

  test "validate_public_https_url accepts public IP literals and returns pinned IP" do
    executor = build_executor()

    assert_equal "1.1.1.1", executor.send(:validate_public_https_url!, "https://1.1.1.1/resource")
  end

  test "add_and_link_resource creates URL resource without embeddability metadata" do
    executor = build_executor()

    result = nil
    assert_difference("Resource.count", 1) do
      executor.stub(:validate_public_https_url!, "93.184.216.34") do
        result = executor.send(
          :execute_add_and_link_resource,
          {
            "resource_type" => "url",
            "description" => "Interactive simulation",
            "category" => "Simulation",
            "tags" => [ "physics" ],
            "url" => "https://example.com/interactive"
          }
        )
      end
    end

    assert_equal "ok", result[:status]
    assert_nil result[:embed_status]
    assert_nil result[:presentation_mode]
  end

  test "exa_content uses default 10,000 chars and query-driven highlights when query is present" do
    captured = {}
    fake_exa = Object.new
    fake_exa.define_singleton_method(:get_contents) do |**kwargs|
      captured[:kwargs] = kwargs
      { "results" => [] }
    end

    executor = build_executor(exa_service: fake_exa)
    executor.send(
      :execute_exa_content,
      {
        "urls" => [ "https://example.com/a" ],
        "max_characters" => nil,
        "query" => "methodology and results"
      }
    )

    assert_equal [ "https://example.com/a" ], captured.dig(:kwargs, :urls)
    assert_equal 10_000, captured.dig(:kwargs, :text, :maxCharacters)
    assert_equal "methodology and results", captured.dig(:kwargs, :highlights, :query)
    assert_equal 4000, captured.dig(:kwargs, :highlights, :maxCharacters)
  end

  test "exa_content omits highlights when query is blank" do
    captured = {}
    fake_exa = Object.new
    fake_exa.define_singleton_method(:get_contents) do |**kwargs|
      captured[:kwargs] = kwargs
      { "results" => [] }
    end

    executor = build_executor(exa_service: fake_exa)
    executor.send(
      :execute_exa_content,
      {
        "urls" => [ "https://example.com/a" ],
        "max_characters" => 50_000,
        "query" => "   "
      }
    )

    assert_equal 10_000, captured.dig(:kwargs, :text, :maxCharacters)
    assert_nil captured.dig(:kwargs, :highlights)
  end

  test "exa_search uses explicit default numResults and search-specific highlight size" do
    captured = {}
    fake_exa = Object.new
    fake_exa.define_singleton_method(:search) do |**kwargs|
      captured[:kwargs] = kwargs
      { "results" => [] }
    end

    executor = build_executor(exa_service: fake_exa)
    executor.send(:execute_exa_search, { "query" => "fractions manipulatives" })

    assert_equal "fractions manipulatives", captured.dig(:kwargs, :query)
    assert_equal 10, captured.dig(:kwargs, :numResults)
    assert_equal false, captured.dig(:kwargs, :contents, :text)
    assert_equal 2000, captured.dig(:kwargs, :contents, :highlights, :maxCharacters)
  end
end
