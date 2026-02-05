require "test_helper"

class Admin::ResourcesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @teacher = users(:admin)
    @other_teacher = users(:admin2)
    @resource = resources(:one) # Belongs to admin
    @other_resource = resources(:two) # Belongs to admin2
    sign_in @teacher
  end

  test "should get index" do
    get admin_resources_path
    assert_response :success
    assert_select "div[id^='resource_']", count: @teacher.resources.count
  end

  test "should get new" do
    get new_admin_resource_path
    assert_response :success
  end

  test "should create resource with applet attributes" do
    assert_difference("Resource.count") do
      assert_difference("Applet.count") do
        post admin_resources_path, params: {
          resource: {
            description: "Resource with applet",
            applet_attributes: {
              title: "My New Applet",
              code: "console.log('test');"
            }
          }
        }
      end
    end

    assert_redirected_to admin_resources_path
    resource = Resource.last
    assert_equal "Applet", resource.category
    assert_equal "My New Applet", resource.applet.title
    assert_equal @teacher, resource.teacher
    assert_equal @teacher, resource.applet.user
  end

  test "should create resource with tags" do
    assert_difference("Resource.count") do
      post admin_resources_path, params: {
        resource: {
          description: "Tagged resource",
          tags: "Math, science, MATH"
        }
      }
    end

    resource = Resource.last
    assert_equal [ "math", "science" ], resource.tags
  end

  test "should show resource" do
    get admin_resource_path(@resource)
    assert_response :success
  end

  test "should get edit" do
    get edit_admin_resource_path(@resource)
    assert_response :success
  end

  test "should update resource" do
    patch admin_resource_path(@resource), params: { resource: { description: "Updated description" } }
    assert_redirected_to admin_resources_path
    assert_equal "Updated description", @resource.reload.description
  end

  test "should destroy resource" do
    assert_difference("Resource.count", -1) do
      delete admin_resource_path(@resource)
    end

    assert_redirected_to admin_resources_path
  end

  test "cannot edit other teacher's resource" do
    get edit_admin_resource_path(@other_resource)
    assert_response :not_found
  end

  test "tag chips renders normalized tags" do
    post tag_chips_admin_resources_path, params: { combobox_values: "Math, science, MATH" }, as: :turbo_stream

    assert_response :success
    assert_includes @response.body, "math"
    assert_includes @response.body, "science"
  end
end
