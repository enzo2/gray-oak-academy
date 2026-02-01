require "application_system_test_case"

class ConversationReviewTest < ApplicationSystemTestCase
  setup do
    @teacher = users(:admin)
    @student = users(:student)
    @student_conversation = conversations(:student_lesson_conversation)

    # Ensure the conversation belongs to the student
    @student_conversation.update!(user: @student)

    # Ensure the student belongs to the teacher
    @student.update!(teacher: @teacher)
  end

  test "teacher sees review mode banner and lesson details on student conversation" do
    sign_in @teacher

    visit conversation_url(@student_conversation)

    assert_text "Review Mode"
    assert_text "Viewing conversation of #{@student.name}"

    # Check for lesson details
    assert_text "Lesson 1"
    assert_text "Math 101"
    assert_text "In Progress"

    assert_no_selector "#message-form"
    assert_no_selector 'sl-textarea[name="message[content]"]'
  end

  test "student sees input form on their own conversation" do
    sign_in @student

    visit conversation_url(@student_conversation)

    assert_no_text "Review Mode"
    assert_selector 'sl-textarea[name="message[content]"]'
  end
end
