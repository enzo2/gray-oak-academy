require "test_helper"

class AutoNameConversationJobTest < ActiveJob::TestCase
  test "renames a default chat title when user text exists" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1")
    conversation.messages.create!(role: :user, content: "Can you help me factor quadratics?")

    fake_client = Object.new
    broadcast_args = nil
    broadcast_kwargs = nil

    LlmServiceRouting.stub(:build_completion_client, fake_client) do
      LlmServiceRouting.stub(:complete_structured_output, { "title" => "Factoring Quadratics Help" }) do
        Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*args, **kwargs) {
          broadcast_args = args
          broadcast_kwargs = kwargs
        }) do
          Turbo::StreamsChannel.stub(:broadcast_update_to, nil) do
            AutoNameConversationJob.perform_now(conversation: conversation)
          end
        end
      end

      assert_equal [ ActionView::RecordIdentifier.dom_id(conversation) ], broadcast_args
      assert_equal ActionView::RecordIdentifier.dom_id(conversation, :sidebar_link), broadcast_kwargs[:target]
      assert_equal "conversations/sidebar_link", broadcast_kwargs[:partial]
      assert_equal conversation.id, broadcast_kwargs[:locals][:conversation].id
      assert_equal conversation.id, broadcast_kwargs[:locals][:current_conversation].id
    end

    assert_equal "Factoring Quadratics Help", conversation.reload.title
  end

  test "does nothing when the conversation has a non-default title" do
    conversation = Conversation.create!(user: users(:admin), title: "Custom Title")
    conversation.messages.create!(role: :user, content: "Hello")

    called = false
    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { called = true }) do
      AutoNameConversationJob.perform_now(conversation: conversation)
    end

    assert_not called
    assert_equal "Custom Title", conversation.reload.title
  end

  test "does nothing when there is no user text content" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1")
    conversation.messages.create!(role: :user, content: "")

    called = false
    LlmServiceRouting.stub(:build_completion_client, ->(**_kwargs) { called = true }) do
      AutoNameConversationJob.perform_now(conversation: conversation)
    end

    assert_not called
    assert_equal "Chat 1", conversation.reload.title
  end

  test "doesn't rename if content is too generic (empty title returned)" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1")
    conversation.messages.create!(role: :user, content: "Hi")

    fake_client = Object.new

    LlmServiceRouting.stub(:build_completion_client, fake_client) do
      LlmServiceRouting.stub(:complete_structured_output, { "title" => "" }) do
        AutoNameConversationJob.perform_now(conversation: conversation)
      end
    end

    assert_equal "Chat 1", conversation.reload.title
  end

  test "requests a stateless client so auto-name does not join the chat response chain" do
    conversation = Conversation.create!(user: users(:admin), title: "Chat 1")
    conversation.messages.create!(role: :user, content: "Help me practice algebra")

    fake_client = Object.new
    captured_kwargs = nil

    LlmServiceRouting.stub(:build_completion_client, ->(**kwargs) {
      captured_kwargs = kwargs
      fake_client
    }) do
      LlmServiceRouting.stub(:complete_structured_output, { "title" => "Algebra Practice" }) do
        Turbo::StreamsChannel.stub(:broadcast_replace_to, nil) do
          AutoNameConversationJob.perform_now(conversation: conversation)
        end
      end
    end

    assert_equal users(:admin), captured_kwargs[:current_user]
    assert_equal conversation, captured_kwargs[:conversation]
    assert_equal false, captured_kwargs[:store]
  end
end
