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

  test "for_completion serializes text, image URL, and input audio content" do
    conversation = conversations(:student_generic_conversation)
    message = Message.create!(conversation: conversation, role: :user, content: "Hello world")
    image = Image.create!(message: message, uri: "http://example.com/img.png", content_type: "image/png")
    audio = Audio.create!(message: message, content_type: "audio/wav")
    message.reload

    audio.define_singleton_method(:base64_for_LLM) { { data: "BASE64DATA", format: "wav" } }
    message.define_singleton_method(:images) { [ image ] }
    message.define_singleton_method(:audios) { [ audio ] }

    payload = Message.for_completion(messages: [ message ], audio: true)
    assert_equal 1, payload.length
    assert_equal "user", payload.first[:role]

    json = payload.to_json
    assert_includes json, "Hello world"
    assert_includes json, image.uri
    assert_includes json, "BASE64DATA"
  end

  test "applet result only messages persist with blank content and are sent to LLM" do
    conversation = conversations(:student_generic_conversation)
    message = Message.create!(
      conversation: conversation,
      role: :user,
      metadata: {
        "applet_results" => [
          {
            "title" => "Fractions game",
            "data" => '{"summary":"Finished 7 of 10","score":7,"total":10}'
          }
        ]
      }
    )

    assert_equal "", message.content

    payload = Message.for_completion(messages: [ message ])
    assert_includes payload.first[:content], "Fractions game"
    assert_includes payload.first[:content], "Finished 7 of 10"
  end

  test "check_context_limit does not notify below adaptive threshold for small models" do
    conversation = conversations(:student_generic_conversation)
    llm = Llm.new(model: "small-model", api_provider: "https://api.limit.test/", context_length: 8_192)
    conversation.define_singleton_method(:llm_in_use) { llm }
    conversation.define_singleton_method(:last_prompt_tokens) { 6_000 } # below 80% (6_553.6)

    message = Message.new(conversation: conversation, role: :user, content: "hi")

    fake_event_reporter = Object.new
    fake_event_reporter.define_singleton_method(:notify) do |_event|
      flunk "Expected no context warning notification below threshold"
    end

    Rails.stub(:event, fake_event_reporter) do
      Turbo::StreamsChannel.stub(:broadcast_update_to, ->(*) { flunk "Expected no flash broadcast below threshold" }) do
        assert_nil message.send(:check_context_limit)
      end
    end
  end
end
