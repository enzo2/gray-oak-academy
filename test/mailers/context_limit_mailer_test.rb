require "test_helper"

class ContextLimitMailerTest < ActionMailer::TestCase
  test "notify_admin" do
    mail = ContextLimitMailer.notify_admin
    assert_equal "Notify admin", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "Hi", mail.body.encoded
  end
end
