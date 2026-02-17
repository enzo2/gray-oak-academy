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
    assert entry.key?("resource_id")
  end

  test "format_collection includes resource_id for text resources" do
    resource = Resource.create!(
      teacher: @teacher,
      category: "Notes",
      description: "Text resource for ID check",
      content: "Lorem ipsum dolor testy test."
    )

    out = Resource.where(teacher: @teacher).format_collection(pretty: false)
    parsed = JSON.parse(out)
    entry = parsed.find { |item| item["resource_id"] == resource.id.to_s }

    assert entry.present?, "expected serialized text resource entry"
    assert_equal "Text resource for ID check", entry["Description"]
    assert_equal "Lorem ipsum dolor testy test.", entry["Content"]
    assert_equal resource.id.to_s, entry["resource_id"]
  end

  test "format_collection truncates long text content" do
    long_content = "x" * (Resource::FORMAT_COLLECTION_CONTENT_LIMIT + 100)
    resource = Resource.create!(
      teacher: @teacher,
      category: "Notes",
      description: "Long text resource",
      content: long_content
    )

    out = Resource.where(teacher: @teacher).format_collection(pretty: false)
    parsed = JSON.parse(out)
    entry = parsed.find { |item| item["resource_id"] == resource.id.to_s }

    assert entry.present?, "expected serialized long text resource entry"
    assert_equal resource.id.to_s, entry["resource_id"]
    truncation_suffix = "... [truncated]"
    assert_equal Resource::FORMAT_COLLECTION_CONTENT_LIMIT + truncation_suffix.length, entry["Content"].length
    assert entry["Content"].end_with?(truncation_suffix)
  end

  test "format_collection returns fallback message when no resources" do
    # Use a teacher with no resources (admin2 has resources in fixtures; create a temp empty scope)
    empty = Resource.where(teacher: users(:student)) # students typically have no resources
    out = empty.format_collection
    assert_includes out, "No resources are yet linked"
  end
end
