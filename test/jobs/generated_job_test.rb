require "test_helper"

class GetLlmCompletionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    ActiveJob::Base.queue_adapter = :test
    @conversation = conversations(:student_generic_conversation)
    @user = @conversation.user
  end

  test "stream handler processes tool_calls and invokes ToolHandlerService" do
    # Ensure a tool exists (fixture provides Chalkboard_URL)
    tool = tools(:one) rescue Tool.first
    # Stub Turbo broadcasts to no-op
    Turbo::StreamsChannel.stub(:broadcast_action_to, true) do
      Turbo::StreamsChannel.stub(:broadcast_update_to, true) do
        # Create a fake OpenaiApiService that will call the stream handler with a tool_calls finish chunk
        fake_service_class = Class.new do
          def initialize(**kwargs)
            @stream_handler = kwargs[:stream_handler]
          end

          def complete(_messages)
            # Simulate streamed chunks: first a content delta to create assistant message, then a tool_calls finish
            if @stream_handler
              # content chunk
              @stream_handler.call({ "delta" => { "content" => "Hello " } })
              # tool_calls chunk fragments
              @stream_handler.call({
                "delta" => {
                  "tool_calls" => [
                    {
                      "index" => 0,
                      "id" => "call-tt",
                      "function" => { "name" => "Chalkboard_URL", "arguments" => '{"url":"https://example.com"}' }
                    }
                  ]
                },
                "finish_reason" => "tool_calls"
              })
            end
            # Return blank (streaming path)
            ""
          end
        end

        # Stub the OpenaiApiService constructor to return our fake
        OpenaiApiService.stub(:new, ->(**kwargs) { fake_service_class.new(**kwargs) }) do
          # Run the job
          assert_enqueued_jobs 0
          GetLlmCompletionJob.perform_now(conversation: @conversation)
          # After job runs, a tool message should have been created
          tool_msg = Message.where(role: "tool").order(created_at: :desc).first
          assert tool_msg.present?, "Expected a tool message to be created from streamed tool_call"
          assert_includes tool_msg.content, "Chalkboard URL", "Tool message content should indicate chalkboard URL change"
        end
      end
    end
  end
end

class GenerateLessonPlanContentJobTest < ActiveSupport::TestCase
  test "job calls LLM and updates lesson_plan content and suggested_resources" do
    teacher = users(:admin)
    lesson = lessons(:one) || Lesson.first
    lesson_plan = lesson.lesson_plan

    # Prepare fake parsed content that matches CONTENT_SCHEMA
    parsed = {
      "lesson_plan" => [
        { "type" => "activity", "details" => "Warm up activity" },
        { "type" => "explain", "details" => "Explain concept" }
      ],
      "suggested_resources" => [
        { "type" => "book", "description" => "Reference book" }
      ]
    }

    fake_service = Object.new
    def fake_service.complete(_messages, **_kwargs)
      { "lesson_plan" => [ { "type" => "activity", "details" => "Warm up activity" }, { "type" => "explain", "details" => "Explain concept" } ], "suggested_resources" => [ { "type" => "book", "description" => "Reference book" } ] }
    end

    OpenaiApiService.stub(:new, ->(**_kwargs) { fake_service }) do
      # Stub broadcasting
      Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
        GenerateLessonPlanContentJob.perform_now(lesson_plan, teacher)
        lesson_plan.reload
        assert_kind_of Array, lesson_plan.content
        assert lesson_plan.content.any? { |h| h["activity"] == "Warm up activity" || h["explain"] == "Explain concept" }
        assert_kind_of Array, lesson_plan.suggested_resources
        assert_equal "Reference book", lesson_plan.suggested_resources.first["book"]
      end
    end
  end
end

class GenerateCourseReportJobTest < ActiveSupport::TestCase
  test "job generates a StudentReport for an enrollment using the LLM" do
    enrollment = enrollments(:one) || Enrollment.first
    teacher = enrollment.course.teacher

    fake_service = Object.new
    def fake_service.complete(_messages, **_kwargs)
      { "summary" => "Great student", "strengths" => [ "math" ], "areas_for_review" => [], "teaching_methods" => [ "examples" ] }
    end

    OpenaiApiService.stub(:new, ->(**_kwargs) { fake_service }) do
      assert_difference "StudentReport.count", 1 do
        GenerateCourseReportJob.perform_now(enrollment)
      end

      report = StudentReport.order(created_at: :desc).first
      assert_equal enrollment.id, report.reportable_id
      assert_equal "Enrollment", report.reportable_type
      assert_equal "ai_generated", report.author_type.to_s
      assert_equal "completed", report.status.to_s
    end
  end
end

class TranscribeAudioJobTest < ActiveSupport::TestCase
  test "transcribes audio, updates message, and destroys audio record" do
    # Create a conversation/message/audio pair
    conv = conversations(:student_generic_conversation)
    msg = Message.create!(conversation: conv, role: :user, content: "")
    audio = Audio.create!(message: msg, content_type: "audio/wav")

    # Mock attached file behavior: provide a tempfile when opened
    mock_file = Object.new
    def mock_file.attached?; true; end
    def mock_file.open
      Tempfile.open([ "audio", ".wav" ]) do |f|
        f.binmode
        f.write("RIFFTEST")
        f.rewind
        yield f
      end
    end
    audio.define_singleton_method(:file) { mock_file }

    # Stub SpeechService to return transcription text
    fake_svc = Object.new
    def fake_svc.transcribe(_tempfile); "Transcribed text"; end

    SpeechService.stub(:new, ->(**_kwargs) { fake_svc }) do
      TranscribeAudioJob.perform_now(audio: audio)
      msg.reload
      assert_equal "Transcribed text", msg.content
      assert_nil Audio.find_by(id: audio.id), "Audio record should be destroyed after transcription"
    end
  end

  test "transcribes mp4 audio (aac) and updates message" do
    # Create a conversation/message/audio pair with mp4 content_type
    conv = conversations(:student_generic_conversation)
    msg = Message.create!(conversation: conv, role: :user, content: "")
    audio = Audio.create!(message: msg, content_type: "audio/mp4")

    # Mock attached file behavior: provide a tempfile when opened
    mock_file = Object.new
    def mock_file.attached?; true; end
    def mock_file.open
      Tempfile.open([ "audio", ".mp4" ]) do |f|
        f.binmode
        f.write("FAKE_MP4")
        f.rewind
        yield f
      end
    end
    audio.define_singleton_method(:file) { mock_file }

    # Stub SpeechService to return transcription text for mp4
    fake_svc = Object.new
    def fake_svc.transcribe(_tempfile); "MP4 Transcribed text"; end

    SpeechService.stub(:new, ->(**_kwargs) { fake_svc }) do
      TranscribeAudioJob.perform_now(audio: audio)
      msg.reload
      assert_equal "MP4 Transcribed text", msg.content
      assert_nil Audio.find_by(id: audio.id), "Audio record should be destroyed after transcription"
    end
  end

  test "transcribes webm audio (opus) and updates message" do
    # Create a conversation/message/audio pair with webm content_type
    conv = conversations(:student_generic_conversation)
    msg = Message.create!(conversation: conv, role: :user, content: "")
    audio = Audio.create!(message: msg, content_type: "audio/webm")

    # Mock attached file behavior: provide a tempfile when opened
    mock_file = Object.new
    def mock_file.attached?; true; end
    def mock_file.open
      Tempfile.open([ "audio", ".webm" ]) do |f|
        f.binmode
        f.write("FAKE_WEBM")
        f.rewind
        yield f
      end
    end
    audio.define_singleton_method(:file) { mock_file }

    # Stub SpeechService to return transcription text for webm
    fake_svc = Object.new
    def fake_svc.transcribe(_tempfile); "WEBM Transcribed text"; end

    SpeechService.stub(:new, ->(**_kwargs) { fake_svc }) do
      TranscribeAudioJob.perform_now(audio: audio)
      msg.reload
      assert_equal "WEBM Transcribed text", msg.content
      assert_nil Audio.find_by(id: audio.id), "Audio record should be destroyed after transcription"
    end
  end
end

class VerifySupportedApiModelsJobTest < ActiveSupport::TestCase
  test "iterates models and calls OpenaiApiService.complete for each when user is superuser and token present" do
    # Promote an existing admin fixture to superuser in DB without validations
    admin = users(:admin)
    admin.update_column(:role, "superuser")

    # Create a SupportedApi with a token
    supported_api = SupportedApi.create!(api_base_uri: "https://api.verify.test/", api_access_token: "tok123", enabled: true)

    called = []
    OpenaiApiService.stub(:new, ->(**kwargs) {
      called << kwargs[:model]
      Object.new.tap do |o|
        def o.complete(_messages); true; end
      end
    }) do
      models = [ "m1", "m2" ]
      VerifySupportedApiModelsJob.perform_now(supported_api_id: supported_api.id, models: models, enqueued_by_user_id: admin.id)
      assert_equal models.sort, called.sort
    end
  end
end
