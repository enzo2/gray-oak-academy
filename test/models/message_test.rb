require "test_helper"

class MessageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  test "enqueues AutoNameConversationJob for first user message in a generic conversation with default title" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1")

    assert_enqueued_with(job: AutoNameConversationJob, args: [ { conversation: conversation } ]) do
      conversation.messages.create!(role: :user, content: "Hello there")
    end
  end

  test "does not enqueue AutoNameConversationJob for lesson conversations" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1", lesson_progress: lesson_progresses(:one))

    assert_no_enqueued_jobs(only: AutoNameConversationJob) do
      conversation.messages.create!(role: :user, content: "Hello")
    end
  end

  test "enqueues AutoNameConversationJob for subsequent user messages while the title is still default" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1")
    conversation.messages.create!(role: :user, content: "First message")
    clear_enqueued_jobs

    assert_enqueued_with(job: AutoNameConversationJob, args: [ { conversation: conversation } ]) do
      conversation.messages.create!(role: :user, content: "Second message")
    end
  end

  test "does not enqueue AutoNameConversationJob after the conversation has been renamed" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1")
    conversation.update!(title: "Custom Title")

    assert_no_enqueued_jobs(only: AutoNameConversationJob) do
      conversation.messages.create!(role: :user, content: "Hello")
    end
  end

  test "enqueues AutoNameConversationJob when a blank user message later gains content (STT flow)" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1")
    message = conversation.messages.create!(role: :user, content: "")
    clear_enqueued_jobs

    assert_enqueued_with(job: AutoNameConversationJob, args: [ { conversation: conversation } ]) do
      message.update!(content: "Transcribed text")
    end
  end
end
