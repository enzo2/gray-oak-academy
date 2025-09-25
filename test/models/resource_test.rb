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
end
