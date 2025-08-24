require "test_helper"

class ResourceFormatCollectionTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:admin)
    @resources = Resource.where(teacher: @teacher)
  end

  test "format_collection returns pretty JSON by default and includes metadata" do
    out = Resource.where(teacher: @teacher).format_collection
    assert out.is_a?(String)
    # Pretty JSON should start with '[' and a newline for pretty_generate
    assert_match(/\A\[\n/, out)
    assert_includes out, "Math textbook"
  end

  test "format_collection with pretty: false returns compact JSON string parseable to array" do
    out = Resource.where(teacher: @teacher).format_collection(pretty: false)
    assert out.is_a?(String)
    parsed = JSON.parse(out)
    assert parsed.is_a?(Array)
    # Ensure at least one resource entry contains expected keys
    entry = parsed.first
    assert entry.key?("Description")
  end

  test "format_collection returns fallback message when no resources" do
    # Use a teacher with no resources (admin2 has resources in fixtures; create a temp empty scope)
    empty = Resource.where(teacher: users(:student)) # students typically have no resources
    out = empty.format_collection
    assert_includes out, "No resources are yet linked"
  end
end
