require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "loads notification types from config" do
    type = Notification::Type.find("lesson.complete")
    assert_equal "student_progress", type.category
    assert_includes type.required_params, "student_name"
    assert_includes type.required_params, "lesson_title"
    assert_includes type.required_params, "report_id"
  end

  test "notification generates message" do
    notification = Notification.new(
      event_type: "lesson.complete",
      params: { "student_name" => "Alice", "lesson_title" => "Math", "report_id" => 1 }
    )
    assert_equal "Alice completed lesson: Math.", notification.message
  end

  test "notification type validates params" do
    type = Notification::Type.find("lesson.complete")

    # Valid params - should not raise
    assert_nothing_raised do
      type.validate_params!({ "student_name" => "Alice", "lesson_title" => "Math", "report_id" => 1 })
    end

    # Missing params - should raise
    error = assert_raises(ArgumentError) do
      type.validate_params!({ "student_name" => "Alice" })
    end
    assert_match(/Missing required params/, error.message)
    assert_match(/lesson_title/, error.message)
  end

  test "unknown notification type raises error on direct find" do
    assert_raises(ArgumentError) do
      Notification::Type.find("unknown.event")
    end
  end

  test "notification uses fallback definition for unknown type" do
    notification = Notification.new(event_type: "unknown.event")

    # Should not raise
    definition = notification.definition
    assert_equal "system", definition.category
    assert_match "Notification: unknown.event", definition.message

    # Message should use fallback
    assert_equal "Notification: unknown.event", notification.message
  end

  test "notification handles missing params gracefully in message" do
    notification = Notification.new(
      event_type: "lesson.complete",
      params: { "student_name" => "Alice" } # Missing lesson_title and report_id
    )
    # Should return a fallback message instead of raising
    assert_match(/notification/, notification.message.downcase)
  end

  test "mark_as_read updates read_at" do
    user = users(:admin)
    notification = Notification.create!(
      recipient: user,
      event_type: "lesson.complete",
      params: { "student_name" => "Test", "lesson_title" => "Test", "report_id" => 1 }
    )

    assert_nil notification.read_at
    assert_not notification.read?

    notification.mark_as_read!

    assert_not_nil notification.read_at
    assert notification.read?
  end
end
