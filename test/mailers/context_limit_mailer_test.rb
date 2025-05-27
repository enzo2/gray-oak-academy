require "test_helper"

class ContextLimitMailerTest < ActionMailer::TestCase
  test "notify_admin" do
    conversation = conversations(:student_conversation)
    mail = ContextLimitMailer.notify_admin(conversation)
    assert_equal "Context Limit Warning", mail.subject
    assert_equal [ "admin@example.com" ], mail.to
    assert_equal [ "webmaster@example.com" ], mail.from
    assert_match "Context Limit Warning", mail.body.encoded
  end
end
