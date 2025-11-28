require "test_helper"
require "open3"

class NodeJsSyntaxCheckerTest < ActiveSupport::TestCase
  test "returns valid for correct javascript" do
    # Create a mock status object that responds to success? with true
    status = Object.new
    status.define_singleton_method(:success?) { true }

    Open3.stub :capture3, [ "", "", status ] do
      result = NodeJsSyntaxChecker.check("console.log('hello');")
      assert result[:valid]
      assert_empty result[:errors]
    end
  end

  test "returns invalid for syntax error" do
    # Create a mock status object that responds to success? with false
    status = Object.new
    status.define_singleton_method(:success?) { false }
    stderr_output = "SyntaxError: Unexpected token"

    Open3.stub :capture3, [ "", stderr_output, status ] do
      result = NodeJsSyntaxChecker.check("invalid js code")
      assert_not result[:valid]
      assert_includes result[:errors], "SyntaxError: Unexpected token"
    end
  end

  test "returns error if node command not found" do
    Open3.stub :capture3, ->(*args) { raise Errno::ENOENT } do
      result = NodeJsSyntaxChecker.check("code")
      assert_not result[:valid]
      assert_match /Node.js not found/, result[:errors].first
    end
  end

  test "returns error if timeout occurs" do
    Timeout.stub :timeout, ->(*args) { raise Timeout::Error } do
      result = NodeJsSyntaxChecker.check("code")
      assert_not result[:valid]
      assert_match /timed out/, result[:errors].first
    end
  end
end
