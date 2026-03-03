require "test_helper"

class Admin::ResourcesControllerTest < ActionDispatch::IntegrationTest
  def setup
    @teacher = users(:admin)
    @other_teacher = users(:admin2)
    @resource = resources(:one) # Belongs to admin
    @other_resource = resources(:two) # Belongs to admin2
    sign_in @teacher
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

  test "should update resource" do
    patch admin_resource_path(@resource), params: { resource: { description: "Updated description" } }
    assert_redirected_to admin_resources_path
    assert_equal "Updated description", @resource.reload.description
  end

  test "should switch text resource to url when content is cleared" do
    resource = Resource.create!(
      teacher: @teacher,
      description: "Text-only resource",
      content: "Quoted text"
    )

    patch admin_resource_path(resource), params: {
      resource: {
        description: "Now a URL resource",
        uri: "https://example.com/updated",
        content: ""
      }
    }

    assert_redirected_to admin_resources_path
    resource.reload
    assert_equal "https://example.com/updated", resource.uri
    assert resource.content.blank?
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

  test "approve marks resource as approved" do
    @resource.update!(approved: false)

    patch approve_admin_resource_path(@resource)

    assert_redirected_to admin_resources_path
    assert_equal true, @resource.reload.approved
  end

  test "check_uri reports embeddable status for URI resources" do
    resource = Resource.create!(
      teacher: @teacher,
      category: "article",
      description: "Embeddable resource",
      uri: "https://example.com/embeddable"
    )

    result = {
      status: "embeddable",
      reason: "No blocking iframe headers detected.",
      final_url: "https://example.com/embeddable",
      x_frame_options: nil,
      csp_frame_ancestors: nil
    }

    UrlEmbeddabilityService.stub(:check, result) do
      post check_uri_admin_resource_path(resource)
    end

    assert_redirected_to admin_resource_path(resource)
    assert_equal "URI check: embeddable. No blocking iframe headers detected.", flash[:notice]
  end

  test "check_uri reports validation failures" do
    error = UrlEmbeddabilityService::ValidationError.new("URL must use HTTPS.")

    UrlEmbeddabilityService.stub(:check, ->(**_kwargs) { raise error }) do
      post check_uri_admin_resource_path(@resource)
    end

    assert_redirected_to admin_resource_path(@resource)
    assert_equal "URI check failed: URL must use HTTPS.", flash[:alert]
  end

  test "index shows pending resources first with highlight and approve action" do
    approved_resource = Resource.create!(
      teacher: @teacher,
      category: "article",
      description: "Approved resource",
      uri: "https://example.com/approved",
      approved: true
    )
    pending_resource = Resource.create!(
      teacher: @teacher,
      category: "article",
      description: "Pending resource",
      uri: "https://example.com/pending",
      approved: false
    )

    get admin_resources_path
    assert_response :success

    pending_index = @response.body.index("id=\"resource_#{pending_resource.id}\"")
    approved_index = @response.body.index("id=\"resource_#{approved_resource.id}\"")
    assert_not_nil pending_index
    assert_not_nil approved_index
    assert_operator pending_index, :<, approved_index

    pending_row_open_tag = @response.body.match(/<div id="resource_#{pending_resource.id}"[^>]*>/)&.to_s
    assert_includes pending_row_open_tag, "bg-amber-50/80"
    assert_includes @response.body, "action=\"#{approve_admin_resource_path(pending_resource)}\""
    assert_includes @response.body, "Approve"
  end

  test "cannot check URI for other teacher resource" do
    post check_uri_admin_resource_path(@other_resource)
    assert_response :not_found
  end
end
