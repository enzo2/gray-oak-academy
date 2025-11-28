require "test_helper"

class AppletTest < ActiveSupport::TestCase
  def setup
    @user = users(:student)
    @applet = Applet.new(title: "Test Applet", code: "console.log('Hello');", user: @user)
  end

  test "valid applet is saved" do
    assert @applet.valid?
    assert @applet.save
  end

  test "requires title" do
    @applet.title = ""
    assert_not @applet.valid?
    assert_includes @applet.errors[:title], "can't be blank"
  end

  test "requires code" do
    @applet.code = ""
    assert_not @applet.valid?
    assert_includes @applet.errors[:code], "can't be blank"
  end

  test "requires user" do
    @applet.user = nil
    assert_not @applet.valid?
    assert_includes @applet.errors[:user], "must exist"
  end

  test "validate_js_syntax adds error on syntax error" do
    # Stub NodeJsSyntaxChecker to return error
    NodeJsSyntaxChecker.stub :check, { valid: false, errors: [ "Unexpected token" ] } do
      @applet.code = "this is not javascript"
      assert_not @applet.valid?
      assert_includes @applet.errors[:code].join, "JavaScript syntax errors"
    end
  end

  test "validate_js_syntax passes on valid syntax" do
    # Stub NodeJsSyntaxChecker to return valid
    NodeJsSyntaxChecker.stub :check, { valid: true, errors: [] } do
      @applet.code = "const a = 1;"
      assert @applet.valid?
    end
  end
end
