require "test_helper"

class ResourceTest < ActiveSupport::TestCase
  fixtures :users

  test "assigns applet user from resource.teacher on create with nested attributes" do
    teacher = users(:admin)
    resource = Resource.new(description: "Test resource", teacher: teacher)

    # Assign nested applet attributes (simulates form submission)
    resource.applet_attributes = { title: "Nested Applet", code: "console.log('hi')" }

    assert resource.valid?, "Resource should be valid before save"
    resource.save!
    assert resource.applet.present?, "Applet should be created"
    assert_equal teacher, resource.applet.user, "Applet user should be assigned from resource.teacher"
  end

  test "assigns applet user on update when adding nested applet attributes" do
    teacher = users(:admin)
    resource = Resource.create!(description: "Existing resource", teacher: teacher)

    # Update the resource with nested applet attributes
    resource.update!(applet_attributes: { title: "Updated Applet", code: "console.log('updated')" })

    assert resource.applet.present?, "Applet should be created on update"
    assert_equal teacher, resource.applet.user, "Applet user should be assigned from resource.teacher on update"
  end

  test "does not overwrite an existing applet.user when present" do
    teacher = users(:admin)
    other_user = users(:admin2)

    # Create an applet that already has a different user
    applet = Applet.create!(title: "Existing Applet", code: "console.log('x')", user: other_user)

    resource = Resource.new(description: "Resource with existing applet", teacher: teacher)
    resource.applet = applet
    resource.save!

    assert_equal other_user, resource.applet.user, "Existing applet.user should not be overwritten by resource assignment"
  end

  test "validates single presence of payload" do
    teacher = users(:admin)
    resource = Resource.new(description: "Invalid resource", teacher: teacher)

    # Attach file AND set URI
    resource.file.attach(io: StringIO.new("test"), filename: "test.txt")
    resource.uri = "https://example.com"

    assert_not resource.valid?
    assert_includes resource.errors[:base], "Only one payload variety (File, URI, Text, or Applet) can be present."

    # Clear URI, add Applet
    resource.uri = nil
    resource.applet = Applet.new(title: "Applet", code: "code", user: teacher)

    assert_not resource.valid?
    assert_includes resource.errors[:base], "Only one payload variety (File, URI, Text, or Applet) can be present."
  end

  test "validates single presence when content and uri are both set" do
    teacher = users(:admin)
    resource = Resource.new(
      description: "Invalid text+uri resource",
      teacher: teacher,
      content: "A quotation",
      uri: "https://example.com"
    )

    assert_not resource.valid?
    assert_includes resource.errors[:base], "Only one payload variety (File, URI, Text, or Applet) can be present."
  end

  test "normalizes tags on assignment" do
    teacher = users(:admin)
    resource = Resource.new(description: "Tagged resource", teacher: teacher, tags: " Math, science ,MATH,,  ")

    assert_equal [ "math", "science" ], resource.tags
  end

  test "normalizes category on assignment" do
    teacher = users(:admin)
    resource = Resource.new(description: "Categorized resource", teacher: teacher, category: "math")

    assert_equal "Math", resource.category
  end

  test "auto converts youtube watch links to embed links" do
    teacher = users(:admin)
    resource = Resource.create!(
      description: "Video resource",
      teacher: teacher,
      uri: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43s"
    )

    assert_equal "https://www.youtube.com/embed/dQw4w9WgXcQ?start=43", resource.uri
  end

  test "auto converts youtu.be links to embed links" do
    teacher = users(:admin)
    resource = Resource.create!(
      description: "Short URL video resource",
      teacher: teacher,
      uri: "https://youtu.be/dQw4w9WgXcQ?t=90"
    )

    assert_equal "https://www.youtube.com/embed/dQw4w9WgXcQ?start=90", resource.uri
  end

  test "rejects youtube urls that are not embed-compatible videos" do
    teacher = users(:admin)
    resource = Resource.new(
      description: "Non-embed YouTube URL",
      teacher: teacher,
      uri: "https://www.youtube.com/channel/UC1234567890"
    )

    assert_not resource.valid?
    assert_includes resource.errors[:uri], "YouTube URLs must use a valid embed-compatible video link."
  end

  test "uri_for_direct_visit converts youtube embed url to watch url" do
    resource = Resource.new(uri: "https://www.youtube.com/embed/dQw4w9WgXcQ?start=43")

    assert_equal "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43s", resource.uri_for_direct_visit
  end

  test "uri_for_direct_visit keeps non-youtube urls unchanged" do
    resource = Resource.new(uri: "https://example.com/article")

    assert_equal "https://example.com/article", resource.uri_for_direct_visit
  end

  test "does not rewrite non-youtube domains that merely end with youtube.com" do
    teacher = users(:admin)
    original_uri = "https://notyoutube.com/watch?v=dQw4w9WgXcQ"

    resource = Resource.create!(
      description: "Non-YouTube URL",
      teacher: teacher,
      uri: original_uri
    )

    assert_equal original_uri, resource.uri
  end
end
