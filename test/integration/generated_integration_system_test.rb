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
    post generate_outline_admin_course_path(course), as: :turbo_stream
    assert_response :success
    assert_enqueued_jobs 1, only: GenerateCourseOutlineJob
  end

  test "lesson_plan generate_content enqueues pipeline job and link_resource links a resource" do
    teacher = users(:admin)
    sign_in(teacher)

    lesson = lessons(:one) || Lesson.first
    lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
    lesson_plan.save!

    # Generate content
    assert_enqueued_jobs 0
    post generate_content_admin_course_lesson_lesson_plan_path(lesson.course, lesson), params: {}, as: :turbo_stream
    assert_response :success
    assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob
    assert_equal "generating_content", lesson_plan.reload.generation_stage

    # Link resource
    resource = resources(:one)
    post link_resource_admin_course_lesson_lesson_plan_path(lesson.course, lesson, resource_id: resource.id), params: {}, as: :turbo_stream
    assert_response :success
    lesson_plan.reload
    assert_includes lesson_plan.resources.map(&:id), resource.id
  end

  test "lesson_plan propose_resources enqueues ProposeResourcesJob after initial generation" do
    teacher = users(:admin)
    sign_in(teacher)

    lesson = lessons(:one)
    lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan
    lesson_plan.update!(generation_stage: "completed")

    AppSetting.stub(:openai_agent_enabled?, true) do
      AppSetting.stub(:exa_enabled?, true) do
        assert_enqueued_jobs 0
        post propose_resources_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
        assert_response :success
        assert_enqueued_jobs 1, only: ProposeResourcesJob
        assert_equal "proposing_resources", lesson_plan.reload.generation_stage

        assert_enqueued_jobs 0, only: ProposeResourcesJob do
          post propose_resources_admin_course_lesson_lesson_plan_path(lesson.course, lesson), as: :turbo_stream
        end
      end
    end
  end
end

class StudentLessonsIntegrationTest < ActionDispatch::IntegrationTest
  test "starting an accessible lesson creates LessonProgress and Conversation for student" do
    student = users(:student)
    sign_in(student)

    lesson = Lesson.create!(
      course: courses(:one),
      title: "Lesson 1.5",
      approx_duration_min: 30,
      goals: "Practice intermediate addition and subtraction"
    )
    lesson.insert_at(1)
    LessonPlan.create!(
      lesson: lesson,
      content: [ { "Warmup" => "Practice intermediate arithmetic." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    # Ensure no progress exists for this student/lesson
    LessonProgress.where(student: student, lesson: lesson).delete_all

    get student_lesson_path(lesson)
    assert_response :success

    lp = LessonProgress.find_by(student: student, lesson: lesson)
    assert lp.present?
    assert lp.conversation.present?
  end

  test "student cannot access a lesson without a lesson plan" do
    student = users(:student)
    sign_in(student)

    lesson_without_plan = Lesson.create!(
      course: courses(:one),
      title: "Lesson Without Plan",
      approx_duration_min: 25,
      goals: "Understand foundational practice"
    )
    lesson_without_plan.insert_at(1)

    assert_no_difference("LessonProgress.count") do
      get student_lesson_path(lesson_without_plan)
    end

    assert_redirected_to student_root_path
    assert_equal "You can only access your next lesson or earlier lessons.", flash[:alert]
  end

  test "student cannot access lessons from another teacher" do
    student = users(:student)
    sign_in(student)

    assert_no_difference("LessonProgress.count") do
      get student_lesson_path(lessons(:two))
    end

    assert_redirected_to student_root_path
    assert_equal "You are not enrolled in this course.", flash[:alert]
  end

  test "student cannot skip ahead past next lesson" do
    student = users(:student)
    sign_in(student)

    next_lesson = Lesson.create!(
      course: courses(:one),
      title: "Next Published Lesson",
      approx_duration_min: 20,
      goals: "Practice decimal place value and estimation"
    )
    next_lesson.insert_at(2)
    LessonPlan.create!(
      lesson: next_lesson,
      content: [ { "Practice" => "Solve decimal place value problems." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    future_lesson = Lesson.create!(
      course: courses(:one),
      title: "Future Lesson",
      approx_duration_min: 20,
      goals: "Apply prior concepts in a more advanced scenario"
    )
    future_lesson.insert_at(4)
    LessonPlan.create!(
      lesson: future_lesson,
      content: [ { "Challenge" => "Solve advanced mixed-problem sets." } ],
      status: "published",
      chalkboard_enabled: true,
      audio: "enabled"
    )

    assert_no_difference("LessonProgress.count") do
      get student_lesson_path(future_lesson)
    end

    assert_redirected_to student_root_path
    assert_equal "You can only access your next lesson or earlier lessons.", flash[:alert]
  end

  test "student lesson shows chalkboard tabs and applet share controls" do
    student = users(:student)
    teacher = users(:admin)
    lesson = lessons(:one)
    lesson_plan = lesson.lesson_plan
    lesson_plan.update!(
      status: "published",
      content: [ { "Activity" => "Work through unit conversion examples." } ]
    )

    resource = Resource.create!(
      teacher: teacher,
      category: "Applet",
      description: "Unit converter for metric and imperial values",
      approved: true
    )
    applet = Applet.create!(
      user: teacher,
      resource: resource,
      title: "Unit Converter",
      code: "console.log('unit converter');"
    )
    lesson_plan.resources << resource unless lesson_plan.resources.exists?(id: resource.id)

    sign_in(student)
    get student_lesson_path(lesson)

    assert_response :success
    assert_includes response.body, "Applets"
    assert_includes response.body, "Whiteboard"
    assert_includes response.body, "chalkboard-share-applet"
    assert_includes response.body, "Unit Converter"
    assert_includes response.body, run_applet_path(applet)
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
