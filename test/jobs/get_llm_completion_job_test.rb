require "test_helper"

class GetLlmCompletionJobStreamingTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  def setup
    ActiveJob::Base.queue_adapter = :test
    @conversation = conversations(:student_generic_conversation)
    @user = @conversation.user
  end

  test "streams assistant content and enqueues TranscribeAudioJob for user audios" do
    # Create a user message that has an attached audio file
    user_msg = @conversation.messages.create!(role: :user, content: "")
    audio = user_msg.audios.create!(content_type: "audio/webm")
    audio.file.attach(io: File.open(Rails.root.join("test/fixtures/files/sample.webm")), filename: "sample.webm", content_type: "audio/webm")

    # Stub OpenaiApiService to return either a streaming or non-streaming fake depending on the call
    OpenaiApiService.stub(:new, ->(**kwargs) {
      handler = kwargs[:stream_handler]
      if handler
        # Streaming fake that calls the provided handler with chunks
        Object.new.tap do |o|
          o.define_singleton_method(:complete) do |*_args|
            handler.call({ "delta" => { "content" => "Hello" } })
            handler.call({ "delta" => { "content" => " world" } })
            handler.call({ "finish_reason" => "stop" })
            handler.call({ "usage" => { "prompt_tokens" => 1, "completion_tokens" => 2, "total_tokens" => 3 } })
            ""
          end
        end
      else
        # Non-streaming fake: return a deterministic transcription for LLM-based STT
        Object.new.tap do |o|
          o.define_singleton_method(:complete) do |*_args|
            "Transcribed fallback text"
          end
        end
      end
    }) do
      # Run the completion job synchronously and process any downstream jobs.
      perform_enqueued_jobs do
        GetLlmCompletionJob.perform_now(conversation: @conversation)
      end
    end

    # The transcription job should have run and removed the audio attachment.
    assert_nil Audio.find_by(id: audio.id), "Audio should have been processed and destroyed"

    # Verify an assistant message was created with the concatenated streamed content
    assistant_msg = @conversation.reload.messages.role_assistant.last
    assert_not_nil assistant_msg, "Assistant message should have been created"
    assert_equal "Hello world", assistant_msg.content
  end
end
