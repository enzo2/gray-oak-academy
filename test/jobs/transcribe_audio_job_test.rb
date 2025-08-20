require "test_helper"

class TranscribeAudioJobUnitTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  def setup
    @student = users(:student)
    @conversation = conversations(:student_generic_conversation)
  end

  test "updates message content and purges audio on successful transcription" do
    msg = @conversation.messages.create!(role: :user, content: "")
    audio = msg.audios.create!(content_type: "audio/wav")
    audio.file.attach(io: File.open(Rails.root.join("test/fixtures/files/sample.wav")), filename: "sample.wav", content_type: "audio/wav")

    SpeechService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        def o.transcribe(_file); "Hello from STT"; end
      end
    }) do
      perform_enqueued_jobs do
        TranscribeAudioJob.perform_later(audio: audio)
      end
    end

    assert_equal "Hello from STT", msg.reload.content
    assert_nil Audio.find_by(id: audio.id), "Audio record should be destroyed after successful transcription"
  end

  test "raises SpeechService::SpeechServiceError and allows retrying when STT fails" do
    msg = @conversation.messages.create!(role: :user, content: "")
    audio = msg.audios.create!(content_type: "audio/wav")
    audio.file.attach(io: File.open(Rails.root.join("test/fixtures/files/sample.wav")), filename: "sample.wav", content_type: "audio/wav")

    SpeechService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |o|
        def o.transcribe(_file); raise SpeechService::SpeechServiceError, "Simulated STT failure"; end
      end
    }) do
      assert_raises(SpeechService::SpeechServiceError) do
        TranscribeAudioJob.new.perform(audio: audio)
      end
      # Ensure audio still exists (job should not delete on failure)
      assert Audio.find_by(id: audio.id), "Audio should not be destroyed when transcription fails"
    end
  end

  test "no-op when audio has no attachment" do
    msg = @conversation.messages.create!(role: :user, content: "")
    audio = msg.audios.create!(content_type: "audio/wav") # no file attached

    # Should not raise
    perform_enqueued_jobs do
      TranscribeAudioJob.perform_later(audio: audio)
    end

    # Audio without attachment should still exist (job returns early)
    assert Audio.find_by(id: audio.id)
  end
end
