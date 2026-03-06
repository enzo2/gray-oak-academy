require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionDispatch::TestProcess::FixtureFile

  setup do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  test "create persists image records from images_data" do
    user = users(:student)
    conversation = conversations(:student_generic_conversation)
    sign_in(user)

    images_data = [
      { "type" => "image/png", "url" => "http://example.com/test.png", "name" => "test.png" }
    ].to_json

    post conversation_messages_path(conversation),
         params: { message: { content: "Hi", images_data: images_data } },
         as: :turbo_stream

    assert_response :success
    message = conversation.reload.messages.last
    assert_equal "Hi", message.content
    assert_equal "user", message.role
    assert_equal "http://example.com/test.png", message.images.first.uri
  end

  test "create routes completion job by provider host" do
    [
      [ "https://openrouter.ai/api/v1/", GetResponsesCompletionJob ],
      [ "https://api.openai.com/v1/", GetResponsesCompletionJob ],
      [ "https://chatgpt.com/backend-api/codex/", GetResponsesCompletionJob ],
      [ "https://api.x.ai/v1/", GetResponsesCompletionJob ],
      [ "https://api.compatible.local/v1/", GetLlmCompletionJob ]
    ].each do |base_uri, expected_job|
      clear_enqueued_jobs
      conversation = sign_in_student_with_teacher_provider!(base_uri: base_uri)
      unexpected_job = expected_job == GetResponsesCompletionJob ? GetLlmCompletionJob : GetResponsesCompletionJob

      assert_enqueued_jobs 1, only: expected_job do
        assert_enqueued_jobs 0, only: unexpected_job do
          post conversation_messages_path(conversation), params: { message: { content: "Hi there" } }, as: :turbo_stream
        end
      end
      assert_response :success
    end
  end

  test "audio_messages routes completion job by provider host and creates user audio message" do
    [
      [ "https://openrouter.ai/api/v1/", GetResponsesCompletionJob ],
      [ "https://chatgpt.com/backend-api/codex/", GetResponsesCompletionJob ],
      [ "https://api.compatible.local/v1/", GetLlmCompletionJob ]
    ].each do |base_uri, expected_job|
      clear_enqueued_jobs
      conversation = sign_in_student_with_teacher_provider!(base_uri: base_uri)
      unexpected_job = expected_job == GetResponsesCompletionJob ? GetLlmCompletionJob : GetResponsesCompletionJob

      # Controller path uses Conversation.find; force permitting so this test isolates routing behavior.
      Conversation.stub(:find, ->(_id) {
        conv = conversations(:student_generic_conversation)
        conv.define_singleton_method(:audio_input_permitted?) { true }
        conv
      }) do
        assert_difference("Audio.count", 1) do
          assert_enqueued_jobs 1, only: expected_job do
            assert_enqueued_jobs 0, only: unexpected_job do
              post audio_messages_conversation_path(conversation),
                   params: { audio: uploaded_audio_fixture("sample.wav", "audio/wav") },
                   as: :turbo_stream
            end
          end
        end
      end

      assert_response :success
      assert conversation.reload.messages.role_user.last.audios.any?
    end
  end

  test "transcribed_messages routes completion job by provider host and persists transcription" do
    [
      [ "https://openrouter.ai/api/v1/", GetResponsesCompletionJob ],
      [ "https://chatgpt.com/backend-api/codex/", GetResponsesCompletionJob ],
      [ "https://api.compatible.local/v1/", GetLlmCompletionJob ]
    ].each do |base_uri, expected_job|
      clear_enqueued_jobs
      conversation = sign_in_student_with_teacher_provider!(base_uri: base_uri)
      unexpected_job = expected_job == GetResponsesCompletionJob ? GetLlmCompletionJob : GetResponsesCompletionJob
      text = "Transcribed text from STT (#{base_uri})"

      with_stubbed_transcription(text) do
        assert_enqueued_jobs 1, only: expected_job do
          assert_enqueued_jobs 0, only: unexpected_job do
            post transcribed_messages_conversation_path(conversation),
                 params: { audio: uploaded_audio_fixture("sample.wav", "audio/wav") },
                 as: :turbo_stream
          end
        end
      end

      assert_response :success
      assert conversation.reload.messages.exists?(content: text), "Expected a transcribed user message to be present"
    end
  end

  private

  def sign_in_student_with_teacher_provider!(base_uri:)
    teacher = users(:admin)
    teacher.setting.update!(llm_api_base_uri: base_uri)
    user = users(:student)
    sign_in(user)
    conversations(:student_generic_conversation)
  end

  def uploaded_audio_fixture(filename, content_type)
    fixture_file_upload("files/#{filename}", content_type)
  rescue StandardError
    Rack::Test::UploadedFile.new(StringIO.new("RIFFTEST"), content_type, original_filename: filename)
  end

  def with_stubbed_transcription(text)
    fake_svc = Object.new
    fake_svc.define_singleton_method(:transcribe) { |_file| text }
    SpeechService.stub(:new, ->(**_kwargs) { fake_svc }) { yield }
  end
end
