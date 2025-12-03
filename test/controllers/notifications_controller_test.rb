require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @user = users(:admin)
    @notification = Notification.create!(
      recipient: @user,
      event_type: "conversation.context_warning",
      params: { "conversation_id" => 123, "user_name" => "Test", "title" => "Test Conversation" },
    )
  end

  test "index requires authentication" do
    get notifications_path
    assert_redirected_to new_user_session_path
  end

  test "index lists notifications for current user" do
    sign_in @user
    get notifications_path

    assert_response :success
    assert_select "main h1", text: "Notifications"
    assert_select "div", text: /Context limit warning/
  end

  test "update marks notification as read" do
    sign_in @user
    patch notification_path(@notification), headers: { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_not_nil @notification.reload.read_at
  end

  test "destroy removes notification" do
    sign_in @user
    delete notification_path(@notification), headers: { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_not Notification.exists?(@notification.id)
  end

  test "mark_all_read marks unread notifications" do
    sign_in @user
    post mark_all_read_notifications_path, headers: { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_empty @user.notifications.unread
  end
end
