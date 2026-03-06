require "test_helper"

class AppletTest < ActiveSupport::TestCase
  def setup
    @user = users(:student)
    @applet = Applet.new(title: "Test Applet", code: "console.log('Hello');", user: @user)
  end

  test "validate_js_syntax adds error on syntax error" do
    NodeJsSyntaxChecker.stub :check, { valid: false, errors: [ "Unexpected token" ] } do
      @applet.code = "this is not javascript"
      assert_not @applet.valid?
      assert_includes @applet.errors[:code].join, "JavaScript syntax errors"
    end
  end

  test "validate_js_syntax passes on valid syntax" do
    NodeJsSyntaxChecker.stub :check, { valid: true, errors: [] } do
      @applet.code = "const a = 1;"
      assert @applet.valid?
    end
  end
end
