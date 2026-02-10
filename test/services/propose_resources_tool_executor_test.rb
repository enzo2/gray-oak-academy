require "test_helper"

class ProposeResourcesToolExecutorTest < ActiveSupport::TestCase
  def build_executor
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    executor = nil

    ExaApiService.stub(:new, ->(**_kwargs) { Object.new }) do
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
end
