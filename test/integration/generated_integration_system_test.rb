require "test_helper"
include ActionDispatch::TestProcess::FixtureFile

class MessagesControllerIntegrationTest < ActionDispatch::IntegrationTest
  test "sending a message with image attachment creates message and image" do
    user = users(:student)
    conversation = conversations(:student_generic_conversation)

    sign_in(user)
    images_data = [
      { "type" => "image/png", "url" => "http://example.com/test.png", "name" => "test.png" }
    ].to_json

    post conversation_messages_path(conversation), params: { message: { content: "Hi", images_data: images_data } }, as: :turbo_stream
    assert_response :success

    conversation.reload
    msg = conversation.messages.last
    assert_equal "Hi", msg.content
    assert_equal "user", msg.role
    assert msg.images.any?
    assert_equal "http://example.com/test.png", msg.images.first.uri
  end

  test "create_audio_message enqueues GetLlmCompletionJob and creates placeholder (wav)" do
    user = users(:student)
    conversation = conversations(:student_generic_conversation)
    sign_in(user)

    audio_file = fixture_file_upload("files/sample.wav", "audio/wav") rescue Rack::Test::UploadedFile.new(StringIO.new("RIFFTEST"), "audio/wav", original_filename: "sample.wav")

    assert_enqueued_jobs 0
    post audio_messages_conversation_path(conversation), params: { audio: audio_file }, as: :turbo_stream
    assert_response :success
    assert_enqueued_jobs 1, only: GetLlmCompletionJob

    conversation.reload
    msg = conversation.messages.last
    assert_equal "user", msg.role
    assert msg.audios.any?
  end

  test "create_audio_message enqueues GetLlmCompletionJob and creates placeholder (webm)" do
    user = users(:student)
    conversation = conversations(:student_generic_conversation)
    sign_in(user)

    audio_file = fixture_file_upload("files/sample.webm", "audio/webm") rescue Rack::Test::UploadedFile.new(StringIO.new("RIFFTEST"), "audio/webm", original_filename: "sample.webm")

    assert_enqueued_jobs 0
    post audio_messages_conversation_path(conversation), params: { audio: audio_file }, as: :turbo_stream
    assert_response :success
    assert_enqueued_jobs 1, only: GetLlmCompletionJob

    conversation.reload
    msg = conversation.messages.last
    assert_equal "user", msg.role
    assert msg.audios.any?
  end

  test "create_audio_message enqueues GetLlmCompletionJob and creates placeholder (mp4)" do
    user = users(:student)
    conversation = conversations(:student_generic_conversation)
    sign_in(user)

    audio_file = fixture_file_upload("files/sample.mp4", "audio/mp4") rescue Rack::Test::UploadedFile.new(StringIO.new("RIFFTEST"), "audio/mp4", original_filename: "sample.mp4")

    assert_enqueued_jobs 0
    post audio_messages_conversation_path(conversation), params: { audio: audio_file }, as: :turbo_stream
    assert_response :success
    assert_enqueued_jobs 1, only: GetLlmCompletionJob

    conversation.reload
    msg = conversation.messages.last
    assert_equal "user", msg.role
    assert msg.audios.any?
  end

  test "create_transcribed_message transcribes via SpeechService and enqueues completion" do
    user = users(:student)
    conversation = conversations(:student_generic_conversation)
    # Start with a fresh conversation
    conversation.messages.destroy_all
    sign_in(user)

    audio_file = fixture_file_upload("files/sample.wav", "audio/wav") rescue Rack::Test::UploadedFile.new(StringIO.new("RIFFTEST"), "audio/wav", original_filename: "sample.wav")

    # Stub SpeechService to return transcription
    fake_svc = Object.new
    def fake_svc.transcribe(_file); "Hello transcribed"; end

    SpeechService.stub(:new, ->(**_kwargs) { fake_svc }) do
      assert_enqueued_jobs 0
      post transcribed_messages_conversation_path(conversation), params: { audio: audio_file }, as: :turbo_stream
      assert_response :success
      assert_enqueued_jobs 1, only: GetLlmCompletionJob
      conversation.reload
      msg = conversation.messages.last
      assert_equal "Hello transcribed", msg.content
    end
  end
end

class AdminControllersIntegrationTest < ActionDispatch::IntegrationTest
  test "creating a course and requesting outline enqueues GenerateCourseOutlineJob" do
    teacher = users(:admin)
    sign_in(teacher)

    # Create course via POST (Turbo stream)
    post admin_courses_path, params: { course: { title: "Test Course", summary: "Test course summary", grade_level: "9" } }, as: :turbo_stream
    assert_response :success

    course = Course.order(created_at: :desc).first
    assert_equal "Test Course", course.title

    assert_enqueued_jobs 0
    post generate_outline_admin_course_path(course)
    assert_response :accepted
    assert_enqueued_jobs 1, only: GenerateCourseOutlineJob
  end

  test "lesson_plan generate_content enqueues GenerateLessonPlanContentJob and link_resource links a resource" do
    teacher = users(:admin)
    sign_in(teacher)

    lesson = lessons(:one) || Lesson.first
    lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan(teacher: teacher)
    lesson_plan.save!

    # Generate content
    assert_enqueued_jobs 0
    post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson), params: {}, as: :json
    assert_response :accepted
    assert_enqueued_jobs 1, only: GenerateLessonPlanContentJob

    # Link resource
    resource = resources(:one)
    post link_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: resource.id), params: {}, as: :turbo_stream
    assert_response :success
    lesson_plan.reload
    assert_includes lesson_plan.resources.map(&:id), resource.id
  end
end

class StudentLessonsIntegrationTest < ActionDispatch::IntegrationTest
  test "starting a lesson creates LessonProgress and Conversation for student" do
    student = users(:student)
    sign_in(student)

    lesson = lessons(:three)
    # Ensure no progress exists for this student/lesson
    LessonProgress.where(student: student, lesson: lesson).delete_all

    get student_lesson_path(lesson)
    assert_response :success

    lp = LessonProgress.find_by(student: student, lesson: lesson)
    assert lp.present?
    assert lp.conversation.present?
  end
end

class TtsAndAudioRecorderIntegrationTest < ActionDispatch::IntegrationTest
  test "tts_stream returns not implemented when speech not configured and streams when configured" do
    # Create an assistant message to stream
    conv = conversations(:student_generic_conversation)
    msg = Message.create!(conversation: conv, role: :assistant, content: "Speak this text")

    user = conv.user
    sign_in(user)

    # When speech not configured
    AppSetting.stub(:speech_configured?, false) do
      get tts_stream_message_path(msg)
      assert_response :not_implemented
    end

    # When speech configured - stub SpeechService to stream chunks
    fake_svc = Object.new
    def fake_svc.sanitize_tts_text(text)
      text.to_s
    end
    def fake_svc.tts_stream(text)
      yield "chunk1"
      yield "chunk2"
    end

    AppSetting.stub(:speech_configured?, true) do
      SpeechService.stub(:new, ->(**_k) { fake_svc }) do
        get tts_stream_message_path(msg)
        # In test environment streaming will still set headers; expect audio content type or success status
        assert_includes @response.content_type, "audio"
        assert_response :success
      end
    end
  end
end
