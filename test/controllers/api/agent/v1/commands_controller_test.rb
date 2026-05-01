require "test_helper"

class Api::Agent::V1::CommandsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @teacher = users(:admin)
    @other_teacher = users(:admin2)
    @key, @token = AgentApiKey.create_with_token!(user: @teacher, name: "Hermes")
  end

  test "status requires bearer token" do
    get api_agent_v1_status_path

    assert_response :unauthorized
    assert_equal false, response.parsed_body["ok"]
  end

  test "status returns capabilities for authenticated teacher" do
    get api_agent_v1_status_path, headers: auth_headers

    assert_response :success
    assert_equal true, response.parsed_body["ok"]
    assert_equal @teacher.id, response.parsed_body.dig("data", "teacher", "id")
    assert_equal false, response.parsed_body.dig("data", "capabilities", "can_publish_lesson_plans")
  end

  test "command endpoint lists teacher scoped courses" do
    post api_agent_v1_command_path,
         params: { command: "list_courses", args: {} }.to_json,
         headers: auth_headers

    assert_response :success
    course_ids = response.parsed_body["data"].map { |course| course["id"] }
    assert_includes course_ids, courses(:one).id
    assert_not_includes course_ids, courses(:two).id
  end

  test "command endpoint lists teacher scoped students" do
    post api_agent_v1_command_path,
         params: { command: "list_students", args: {} }.to_json,
         headers: auth_headers

    assert_response :success
    student_ids = response.parsed_body["data"].map { |student| student["id"] }
    assert_includes student_ids, users(:student).id
    assert_not_includes student_ids, users(:student2).id
  end

  test "command endpoint rejects non-catalog operation method names" do
    post api_agent_v1_command_path,
         params: { command: "destroy!", args: {} }.to_json,
         headers: auth_headers

    assert_response :not_found
    assert_equal false, response.parsed_body["ok"]
    assert_equal "unknown_command", response.parsed_body.dig("error", "code")
  end

  test "teacher key cannot read another teacher course" do
    post api_agent_v1_command_path,
         params: { command: "get_course", args: { course_id: courses(:two).id } }.to_json,
         headers: auth_headers

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
  end

  test "superuser key is scoped to the issuing user's own teacher records" do
    superuser = users(:super_user)
    course = Course.create!(
      teacher: superuser,
      title: "Superuser Course",
      summary: "A course owned by the superuser account.",
      grade_level: "1"
    )
    _key, token = AgentApiKey.create_with_token!(user: superuser, name: "Super Hermes")

    post api_agent_v1_command_path,
         params: { command: "list_courses", args: {} }.to_json,
         headers: auth_headers(token)

    assert_response :success
    course_ids = response.parsed_body["data"].map { |item| item["id"] }
    assert_includes course_ids, course.id
    assert_not_includes course_ids, courses(:one).id
    assert_not_includes course_ids, courses(:two).id

    post api_agent_v1_command_path,
         params: { command: "get_course", args: { course_id: courses(:one).id } }.to_json,
         headers: auth_headers(token)

    assert_response :not_found
  end

  test "update_lesson_plan_draft rejects publish attempts" do
    post api_agent_v1_command_path,
         params: {
           command: "update_lesson_plan_draft",
           args: { lesson_id: lessons(:one).id, lesson_plan_status: "published" }
         }.to_json,
         headers: auth_headers

    assert_response :forbidden
    assert_equal "publishing_forbidden", response.parsed_body.dig("error", "code")
  end

  test "update_lesson_plan_draft rejects existing published lesson plan" do
    lesson_plans(:one).update_column(:status, "published")

    post api_agent_v1_command_path,
         params: {
           command: "update_lesson_plan_draft",
           args: {
             lesson_id: lessons(:one).id,
             lesson_plan_content: [ { type: "Warmup", details: "Count by twos." } ]
           }
         }.to_json,
         headers: auth_headers

    assert_response :forbidden
    assert_equal "published_lesson_plan_locked", response.parsed_body.dig("error", "code")
    assert_equal "published", lesson_plans(:one).reload.status
  end

  test "update_lesson_plan_draft permits draft edits" do
    post api_agent_v1_command_path,
         params: {
           command: "update_lesson_plan_draft",
           args: {
             lesson_id: lessons(:one).id,
             lesson_plan_content: [ { type: "Warmup", details: "Count by twos." } ]
           }
         }.to_json,
         headers: auth_headers

    assert_response :success
    assert_equal "draft", response.parsed_body.dig("data", "lesson_plan", "status")
    assert_equal [ { "Warmup" => "Count by twos." } ], lesson_plans(:one).reload.content
  end

  test "create_resource supports generated file upload payloads" do
    pdf_data = Base64.strict_encode64("%PDF-1.4 generated handout")

    assert_difference("Resource.count", 1) do
      post api_agent_v1_command_path,
           params: {
             command: "create_resource",
             args: {
               description: "Generated PDF handout",
               category: "Handout",
               file_base64: pdf_data,
               filename: "handout.pdf",
               content_type: "application/pdf",
               lesson_id: lessons(:one).id
             }
           }.to_json,
           headers: auth_headers
    end

    assert_response :success
    resource = Resource.order(:created_at).last
    assert_equal false, resource.approved
    assert resource.file.attached?
    assert_includes lesson_plans(:one).reload.resources, resource
  end

  test "create_resource with invalid lesson id does not create resource" do
    assert_no_difference("Resource.count") do
      post api_agent_v1_command_path,
           params: {
             command: "create_resource",
             args: {
               description: "Orphan handout",
               category: "Handout",
               content: "Practice",
               lesson_id: -1
             }
           }.to_json,
           headers: auth_headers
    end

    assert_response :not_found
  end

  test "create_resource does not link pending resource to published lesson plan" do
    lesson_plans(:one).update_column(:status, "published")

    assert_no_difference("Resource.count") do
      post api_agent_v1_command_path,
           params: {
             command: "create_resource",
             args: {
               description: "Pending handout",
               category: "Handout",
               content: "Practice",
               lesson_id: lessons(:one).id
             }
           }.to_json,
           headers: auth_headers
    end

    assert_response :conflict
    assert_equal "pending_resource_on_published_plan", response.parsed_body.dig("error", "code")
  end

  test "save_applet_as_resource does not create resource when pending link is forbidden" do
    lesson_plans(:one).update_column(:status, "published")
    applet = @teacher.applets.create!(title: "Generated activity", code: "console.log('activity');")

    assert_no_difference("Resource.count") do
      post api_agent_v1_command_path,
           params: {
             command: "save_applet_as_resource",
             args: {
               applet_id: applet.id,
               lesson_id: lessons(:one).id
             }
           }.to_json,
           headers: auth_headers
    end

    assert_response :conflict
    assert_equal "pending_resource_on_published_plan", response.parsed_body.dig("error", "code")
    assert_nil applet.reload.resource
  end

  test "agent key cannot link orphaned global resources" do
    resource = Resource.create!(description: "Global text", content: "Shared but not owned", teacher: nil)

    post api_agent_v1_command_path,
         params: {
           command: "link_resource_to_lesson_plan",
           args: { lesson_plan_id: lesson_plans(:one).id, resource_id: resource.id }
         }.to_json,
         headers: auth_headers

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
    assert_not_includes lesson_plans(:one).reload.resources, resource
  end

  test "generate_lesson_plan returns actionable generation failures" do
    captured_kwargs = nil

    GenerateLessonPlanContentJob.stub(:perform_now, ->(*_args, **kwargs) {
      captured_kwargs = kwargs
      raise StandardError, "provider unavailable"
    }) do
      post api_agent_v1_command_path,
           params: {
             command: "generate_lesson_plan",
             args: { lesson_id: lessons(:one).id, action: "generate_content" }
           }.to_json,
           headers: auth_headers
    end

    assert_response :unprocessable_content
    assert_equal true, captured_kwargs[:raise_on_error]
    assert_equal "generation_failed", response.parsed_body.dig("error", "code")
    assert_equal "Failed to generate lesson plan content: provider unavailable", response.parsed_body.dig("error", "message")
  end

  test "generate_course_lessons returns actionable generation failures" do
    captured_kwargs = nil

    GenerateCourseLessonsJob.stub(:perform_now, ->(*_args, **kwargs) {
      captured_kwargs = kwargs
      raise StandardError, "provider unavailable"
    }) do
      post api_agent_v1_command_path,
           params: {
             command: "generate_course_lessons",
             args: { course_id: courses(:one).id, replace_existing_lessons: true }
           }.to_json,
           headers: auth_headers
    end

    assert_response :unprocessable_content
    assert_equal true, captured_kwargs[:raise_on_error]
    assert_equal "generation_failed", response.parsed_body.dig("error", "code")
    assert_equal "Failed to generate course lessons: provider unavailable", response.parsed_body.dig("error", "message")
  end

  test "malformed json returns envelope and audit event" do
    assert_difference("AgentApiEvent.count", 1) do
      post api_agent_v1_command_path,
           params: "command:list_courses",
           headers: auth_headers
    end

    assert_response :bad_request
    assert_equal false, response.parsed_body["ok"]
    assert_equal "invalid_json", response.parsed_body.dig("error", "code")
    assert_equal "invalid_json", AgentApiEvent.last.error_code
    assert_equal 400, AgentApiEvent.last.status
  end

  test "generate_course_outline returns actionable generation failures" do
    GenerateCourseOutlineJob.stub(:perform_now, ->(*) { raise StandardError, "provider unavailable" }) do
      post api_agent_v1_command_path,
           params: {
             command: "generate_course_outline",
             args: { course_id: courses(:one).id, action: "generate_outline" }
           }.to_json,
           headers: auth_headers
    end

    assert_response :unprocessable_content
    assert_equal false, response.parsed_body["ok"]
    assert_equal "generation_failed", response.parsed_body.dig("error", "code")
    assert_equal "Failed to generate course outline: provider unavailable", response.parsed_body.dig("error", "message")
  end

  test "skill endpoint includes hard lines" do
    get api_agent_v1_skill_path, headers: auth_headers

    assert_response :success
    assert_includes response.body, "/api/agent/v1"
    assert_includes response.body, "Do not publish lesson plans"
    assert_includes response.body, "Do not conduct lessons"
    assert_includes response.body, "Teaching principles"
    assert_includes response.body, "Be friendly and encouraging"
    assert_includes response.body, "One draft lesson plan per lesson"
    assert_includes response.body, "offline/reflection-style lessons"
    assert_includes response.body, "Synchronous generator commands may replace generated content"
    assert_includes response.body, "GET /help?command=COMMAND"
    assert_includes response.body, "GET /help?topic=TOPIC"
    assert_includes response.body, "External agents must not answer those teacher questions"
  end

  test "help lists operational topics without provenance fields" do
    get api_agent_v1_help_path, headers: auth_headers

    assert_response :success
    topics = response.parsed_body.dig("data", "help_topics")
    assert_includes topics.keys, "applets"
    assert_nil topics.dig("applets", "source_tool_names")
    assert_nil topics.dig("applets", "source_tools")
    assert_nil topics.dig("applets", "source_prompt_categories")
    assert_includes response.parsed_body.dig("data", "commands").keys, "upsert_applet"
  end

  test "command help includes related help topics" do
    get api_agent_v1_help_path(command: "upsert_applet"), headers: auth_headers

    assert_response :success
    assert_equal "upsert_applet", response.parsed_body.dig("data", "command")
    assert_includes response.parsed_body.dig("data", "related_help_topics"), "applets"
    assert_includes response.parsed_body.dig("data", "details", "guidance"), "code must be raw JavaScript module code only; do not include Markdown fences or executable-block attributes."
  end

  test "create_resource help documents applet payloads" do
    get api_agent_v1_help_path(command: "create_resource"), headers: auth_headers

    assert_response :success
    assert_equal "optional {title, code}", response.parsed_body.dig("data", "details", "args", "applet_attributes")
    assert_includes response.parsed_body.dig("data", "details", "guidance"), "Provide exactly one payload: uri, content, file_base64, or applet_attributes."
    assert_includes response.parsed_body.dig("data", "related_help_topics"), "resources"
    assert_includes response.parsed_body.dig("data", "related_help_topics"), "applets"
  end

  test "topic help returns operational app context without raw prompt text" do
    get api_agent_v1_help_path(topic: "applets"), headers: auth_headers

    assert_response :success
    details = response.parsed_body.dig("data", "details")
    assert_nil details["source_tool_names"]
    assert_nil details["source_tools"]
    assert_nil details["source_prompt_categories"]
    assert_includes details["guidance"], "Saved applet `code` must be raw JavaScript module code, not a Markdown fenced code block."
    assert_includes details["guidance"], "Applet code runs in a sandboxed iframe and should mount UI into `document.getElementById(\"sandbox\")`."
    assert_not_includes details.to_json, "Follow these generative guidelines"
  end

  test "unknown help topic returns not found envelope" do
    get api_agent_v1_help_path(topic: "unknown"), headers: auth_headers

    assert_response :not_found
    assert_equal "unknown_help_topic", response.parsed_body.dig("error", "code")
  end

  test "skill endpoint uses teacher-specific teaching principles" do
    Prompt.create!(
      title: "Admin Teaching Principles",
      category: "teaching_principles",
      prompt: "Use the teacher's custom Socratic workshop style.",
      teacher: @teacher
    )

    get api_agent_v1_skill_path, headers: auth_headers

    assert_response :success
    assert_includes response.body, "Use the teacher's custom Socratic workshop style."
    assert_not_includes response.body, "Be friendly and encouraging."
  end

  test "authenticated commands are audited" do
    assert_difference("AgentApiEvent.count", 1) do
      post api_agent_v1_command_path,
           params: { command: "get_course", args: { course_id: courses(:one).id } }.to_json,
           headers: auth_headers
    end

    event = AgentApiEvent.last
    assert_equal @teacher, event.user
    assert_equal @key, event.agent_api_key
    assert_equal "get_course", event.command
    assert_equal [ courses(:one).id ], event.record_ids["courses"]
  end

  private

  def auth_headers(token = @token)
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end
end
