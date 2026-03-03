require "json/repair"
require "securerandom"

class ToolExecutionService
  class ToolExecutionError < StandardError; end
  include ActionView::RecordIdentifier
  WEB_DEFAULT_SEARCH_RESULTS = 10
  WEB_MAX_SEARCH_RESULTS = 20
  WEB_SEARCH_HIGHLIGHT_MAX_CHARS = 2_000
  WEB_CONTENT_TEXT_MAX_CHARS = 4_000
  WEB_CONTENT_HIGHLIGHT_MAX_CHARS = 4_000
  WEB_MAX_CONTENT_URLS = 5

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
    @user = conversation.user
  end

  def execute_tool_call(tool_call)
    @tool_call_id = tool_call[:id]

    begin
      # Find the tool by name (case-insensitive to handle LLM capitalization errors)
      tool = Tool.where("LOWER(name) = LOWER(?)", tool_call[:name].to_s).first
      raise ToolExecutionError, "Tool '#{tool_call[:name]}' not found" unless tool

      # Normalize name for internal comparisons and dispatch
      tool_name = normalized_name(tool.name)

      # Prevent runaway tool-call loops: disallow executing new tools if the conversation
      # already has too many consecutive tool messages without an intervening user message.
      if runaway_tool_call_limit_exceeded?(10)
        raise ToolExecutionError, "Permission denied: consecutive tool call limit reached. User must confirm before next tool call."
      end

      # Authorization: ensure caller is allowed to run this tool.
      allowed_tools = Tool.enabled_for_user(@user)
      unless allowed_tools.exists?(id: tool.id)
        raise ToolExecutionError, "Permission denied: this tool is not available to you"
      end

      # Validate arguments against tool specifications, and parse to @args hash.
      @args = validate_and_parse_arguments(tool, tool_call[:arguments])

      # Execute the tool based on its normalized name.
      # Ensure each tool method calls create_tool_message upon completion.
      method_name = :"execute_#{tool_name}"
      if respond_to?(method_name, true)
        send(method_name)
      else
        raise ToolExecutionError, "Tool '#{tool.name}' execution not implemented!"
      end
    rescue ToolExecutionError => e
      Rails.logger.error("ToolExecutionError: #{e.message}")
      # Notify the LLM of the error, not the user, since the LLM called the tool.
      create_tool_message("Tool execution resulted in error: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("Unexpected tool execution error: #{e.message}")
      create_tool_message("Tool execution resulted in error: #{e.message}")
    end
  end

  def execute_tool_calls(tool_calls)
    return if tool_calls.empty?
    tool_calls.each do |tc|
      execute_tool_call({
        id: tc[:id],
        name: tc.dig(:function, :name),
        arguments: tc.dig(:function, :arguments)
      })
    end
  end

  private

  def normalized_name(name)
    name.to_s.strip.downcase
  end

  # Tolerant JSON parse + schema-aware coercion for common primitive types.
  def validate_and_parse_arguments(tool, arguments)
    # Parse JSON arguments
    if arguments.blank?
      parsed_arguments = {}
    else
      begin
        parsed_arguments = JSON.parse(arguments)
      rescue JSON::ParserError
        # If invalid, try repairing the JSON
        begin
          Rails.logger.debug "Invalid JSON in tool arguments, attempting to repair: #{arguments}"
          repaired_arguments = JSON.repair(arguments)
          parsed_arguments = JSON.parse(repaired_arguments)
          Rails.logger.debug "Repaired JSON successfully."
        rescue JSON::ParserError, JSON::JSONRepairError
          raise ToolExecutionError, "Invalid JSON in tool arguments, unable to repair."
        end
      end
    end

    unless parsed_arguments.is_a?(Hash)
      raise ToolExecutionError, "Tool arguments must be a JSON object"
    end

    # Get required parameters from tool specifications

    required_params = tool.specifications.dig("parameters", "required") || []
    # Check all required parameters are present
    missing_params = required_params - parsed_arguments.keys
    unless missing_params.empty?
      raise ToolExecutionError, "Missing required parameters: #{missing_params.join(', ')}"
    end

    # Validate argument types if specified in the tool
    properties = tool.specifications.dig("parameters", "properties") || {}
    properties.each do |param_name, param_spec|
      next unless parsed_arguments.key?(param_name)
      expected_type = param_spec["type"]

      case expected_type
      when "string"
        unless parsed_arguments[param_name].is_a?(String)
          parsed_arguments[param_name] = parsed_arguments[param_name].to_s
        end
      when "array"
        unless parsed_arguments[param_name].is_a?(Array)
          raise ToolExecutionError, "Parameter '#{param_name}' must be an array"
        end
      when "integer"
        val = parsed_arguments[param_name]
        if val.is_a?(Integer)
          # ok
        elsif val.is_a?(String) && val.match?(/\A-?\d+\z/)
          parsed_arguments[param_name] = val.to_i
        else
          raise ToolExecutionError, "Parameter '#{param_name}' must be an integer"
        end
      when "number"
        val = parsed_arguments[param_name]
        if val.is_a?(Numeric)
          # ok
        elsif val.is_a?(String) && val.match?(/\A-?\d+(\.\d+)?\z/)
          parsed_arguments[param_name] = val.include?(".") ? val.to_f : val.to_i
        else
          raise ToolExecutionError, "Parameter '#{param_name}' must be a number"
        end
      when "boolean"
        val = parsed_arguments[param_name]
        if val == true || val == false
          # ok
        elsif val.is_a?(String) && %w[true false].include?(val.downcase)
          parsed_arguments[param_name] = (val.downcase == "true")
        else
          raise ToolExecutionError, "Parameter '#{param_name}' must be a boolean"
        end
      when "object"
        unless parsed_arguments[param_name].is_a?(Hash)
          raise ToolExecutionError, "Parameter '#{param_name}' must be an object"
        end
      else
        Rails.logger.debug "Skipping strict validation for parameter '#{param_name}' with type '#{expected_type}'"
      end

      # Additional enum validation when an 'enum' is specified in the parameter schema.
      # This guards against typos such as "publshed" for enum-backed fields like status.
      if param_spec["enum"] && parsed_arguments.key?(param_name)
        allowed_values = param_spec["enum"]
        # Allow numeric coercion already performed above to match enum types
        unless allowed_values.include?(parsed_arguments[param_name])
          raise ToolExecutionError, "Parameter '#{param_name}' must be one of: #{allowed_values.join(', ')}"
        end
      end
    end

    # Enforce strict_mode: reject unexpected parameters when strict_mode is set on the Tool
    if tool.specifications["strict_mode"]
      allowed_keys = (properties || {}).keys.map(&:to_s)
      extra_keys = parsed_arguments.keys.map(&:to_s) - allowed_keys
      unless extra_keys.empty?
        raise ToolExecutionError, "Unexpected parameters provided: #{extra_keys.join(', ')}"
      end
    end

    # Schema-level validation (strict, nested, and additionalProperties) using JSONSchemer
    begin
      param_schema = tool.specifications.dig("parameters")
      if param_schema.present?
        schemer = JSONSchemer.schema(param_schema)
        unless schemer.valid?(parsed_arguments)
          errors = schemer.validate(parsed_arguments).map do |e|
            ptr = e["data_pointer"].presence || "#"
            "#{ptr}: #{e['error']}"
          end
          raise ToolExecutionError, "Arguments failed schema validation: #{errors.first(5).join('; ')}"
        end
      end
    rescue StandardError => e
      # If a tool was seeded with an invalid schema, surface a clear error
      raise ToolExecutionError, "Error validating JSON schema: #{e.message}"
    end

    # Return the validated and parsed arguments
    parsed_arguments
  end

  # -- Security helpers --
  def current_teacher
    return @user if @user.role_teacher?
    return @user.teacher if @user.teacher.present?
    raise ToolExecutionError, "No teacher associated with current user"
  end

  def applet_scope_for_user
    case @user.role
    when "student" # Allow own or teacher's applets.
      Applet.where(user_id: [ @user.id, @user.teacher_id ].compact)
    when "admin" # Allow own or students' applets.
      Applet.where(user_id: @user.id)
            .or(Applet.where(user_id: @user.students.select(:id)))
    when "superuser"
      Applet.all
    else
      Applet.none
    end
  end

  def runaway_tool_call_limit_exceeded?(limit = 10)
    # Determine the timestamp of the most recent user message in the conversation.
    last_user = @conversation.messages.where(role: "user").reorder(created_at: :desc).first
    if last_user
      # Count assistant/tool messages after the last user message.
      recent_count = @conversation.messages.where("created_at > ?", last_user.created_at)
                                          .where(role: "tool")
                                          .count
    else
      # No user messages at all — count assistant/tool messages
      recent_count = @conversation.messages.where(role: "tool").count
    end
    Rails.logger.warn "Tool calls exceeded limit: #{recent_count} >= #{limit}" if recent_count >= limit
    recent_count >= limit
  end

  # -- Tool execution methods --

  def execute_show_on_chalkboard
    url = @args["url"].to_s.strip.presence
    resource_id = @args["resource_id"].to_s.strip.presence
    provided_argument_count = [ url, resource_id ].count(&:present?)

    unless provided_argument_count == 1
      raise ToolExecutionError, "Provide exactly one argument: either 'url' or 'resource_id'."
    end

    if url.present?
      execute_chalkboard_url_payload(url, tab_title: "Web Link")
      return
    end

    resource = find_and_authorize_chalkboard_resource!(resource_id)
    enforce_lesson_resource_scope!(resource)
    execute_chalkboard_resource_payload(resource)
  end

  def execute_complete_lesson
    # Get the current lesson from the conversation
    student = @user
    lesson_progress = @conversation.lesson_progress
    lesson = lesson_progress&.lesson

    raise ToolExecutionError, "No active lesson found for this conversation" unless lesson
    raise ToolExecutionError, "No student found for this conversation" unless student
    raise ToolExecutionError, "This lesson already was completed and has a report." if lesson_progress&.student_report&.status_completed?

    # Validate the required fields in args
    unless @args["summary"].present?
      raise ToolExecutionError, "Fields missing or invalid: summary"
    end

    # Create the student report
    report = StudentReport.create!(
      student: student,
      teacher: lesson.teacher,
      reportable: lesson_progress, # Associate the report with the LessonProgress, which will cause lesson_progress.completed? to return true
      progress_data: @args,
      author_type: :ai_generated,
      status: :completed
    )

    # Update analytics
    duration = lesson_progress.calculate_duration
    lesson_progress.update!(completed_at: report.created_at, duration: duration)

    Rails.logger.debug("Lesson completed and student report generated for lesson: #{lesson.id}, student: #{student.id}")
    Rails.logger.debug("Report: #{@args}")

    # Broadcast completion message to the conversation
    broadcast_lesson_completed
    create_tool_message("Confirmation: Lesson completed and student report generated successfully. Any further conversation will not be reflected in the progress report. Don't attempt to continue the lesson, but inform that you're still available for any questions. If the student decides to continue, you can engage, but inform them that any progress won't be reflected in future lessons.")
  end

  def execute_python_sandbox
    code = @args["code"]
    result = PythonCodeExecutorService.execute(code)
    if result["error"] # I.e. HTTP error from terrarium
      Rails.logger.error("PythonCodeExecutorService error: #{result["error"]}")
      raise ToolExecutionError, "Python code execution service error: #{result["error"]}"
    else
      content = result.to_json
      Rails.logger.debug "PythonCodeExecutorService output: #{content}"
      create_tool_message(content)
    end
  end

  def execute_web
    action = @args["action"].to_s.strip.downcase

    payload = case action
    when "search"
      query = @args["query"].to_s.strip
      raise ToolExecutionError, "query is required for action 'search'." if query.blank?

      num_results = @args["num_results"].to_i
      num_results = WEB_DEFAULT_SEARCH_RESULTS if num_results <= 0
      num_results = [ num_results, WEB_MAX_SEARCH_RESULTS ].min

      ExaApiService.new(current_user: @user, conversation: @conversation).search(
        query: query,
        numResults: num_results,
        contents: {
          text: false,
          highlights: { maxCharacters: WEB_SEARCH_HIGHLIGHT_MAX_CHARS }
        }
      )
    when "answer"
      query = @args["query"].to_s.strip
      raise ToolExecutionError, "query is required for action 'answer'." if query.blank?

      ExaApiService.new(current_user: @user, conversation: @conversation).answer(query: query)
    when "content"
      urls = Array(@args["urls"]).map { |u| u.to_s.strip }.reject(&:blank?).uniq
      raise ToolExecutionError, "urls is required for action 'content'." if urls.blank?
      if urls.size > WEB_MAX_CONTENT_URLS
        raise ToolExecutionError, "A maximum of #{WEB_MAX_CONTENT_URLS} URLs is allowed for action 'content'."
      end

      query = @args["query"].to_s.strip

      options = { text: { maxCharacters: WEB_CONTENT_TEXT_MAX_CHARS } }
      if query.present?
        options[:highlights] = {
          query: query,
          maxCharacters: WEB_CONTENT_HIGHLIGHT_MAX_CHARS
        }
      end

      ExaApiService.new(current_user: @user, conversation: @conversation).get_contents(urls: urls, **options)
    else
      raise ToolExecutionError, "action must be one of: search, answer, content."
    end

    create_tool_message(JSON.pretty_generate(payload))
  rescue OpenAiError => e
    raise ToolExecutionError, e.message
  end

  def execute_list_students
    students = current_teacher.students.select(:id, :first_name, :last_name, :email)
    payload = students.map { |s| { id: s.id, name: s.name, email: s.email } }
    create_tool_message(JSON.pretty_generate(payload))
  end

  def execute_list_courses
    if @user.role_student?
      # Students can only list their own courses
      courses = @user.enrollments.in_progress.includes(:course).map(&:course)
    else
      # Teachers can list their taught courses
      courses = current_teacher.taught_courses.select(:id, :title, :grade_level, :status)
    end
    create_tool_message(JSON.pretty_generate(courses.as_json(only: [ :id, :title, :grade_level, :status ])))
  end

  def execute_get_course_details
    course_id = @args["course_id"].to_i
    course = current_teacher.taught_courses.find_by(id: course_id)
    raise ToolExecutionError, "Course not found" unless course

    if @user.role_student?
      enrollment = @user.enrollments.find_by(course: course)
      raise ToolExecutionError, "Permission denied; user not enrolled in this course" unless enrollment
    else
      # Teachers can view other teachers' courses
    end

    create_tool_message(JSON.pretty_generate(course.for_llm))
  end

  def execute_get_lesson_details
    lesson_id = @args["lesson_id"].to_i
    show_on_chalkboard = @args["show_on_chalkboard"]
    lesson = Lesson.find_by(id: lesson_id)
    raise ToolExecutionError, "Lesson not found" unless lesson

    # Students can view lessons if enrolled in the course
    if @user.role_student?
      enrollment = @user.enrollments.find_by(course: lesson.course)
      raise ToolExecutionError, "Permission denied; user not enrolled in this course" unless enrollment
    end
    unless lesson.course.teacher == current_teacher
      # Teachers can only view their own lessons
      raise ToolExecutionError, "Permission denied, course does not belong to the current user"
    end

    output = JSON.pretty_generate(lesson.for_llm)
    # Optionally render the lesson and lesson plan to the chalkboard as markdown
    if show_on_chalkboard == false
      create_tool_message(output)
    else
      broadcast_chalkboard_lesson(lesson)
      create_tool_message(output + "\n\nAlso sending these details to chalkboard now for display: done.")
    end
  end

  def execute_get_student_reports
    student_id = @args["student_id"].to_i

    # Enforce that students may only fetch their own reports; teachers can fetch any of their students' reports.
    caller = @user
    if caller.role_student?
      raise ToolExecutionError, "Permission denied; students can only view their own reports" unless caller.id == student_id
      student = caller
    else
      # Caller is a teacher. Ensure the target student belongs to this teacher.
      student = current_teacher.students.find_by(id: student_id)
      raise ToolExecutionError, "Student not found" unless student
    end

    # Reports will include both lesson reports and course reports
    reports = student.student_reports.where(teacher: current_teacher).order(created_at: :desc)

    payload = {
      student: { id: student.id, name: student.name },
      report_counts: { lessons: reports.lesson_reports.count, courses: reports.course_reports.count },
      reports_markdown: reports.map(&:to_markdown).join("\n\n---\n\n")
    }
    create_tool_message(JSON.pretty_generate(payload))
  end

  def execute_get_student_profile
    student_id = @args["student_id"].to_i
    focus = @args["focus"].to_s.strip.presence
    show_on_chalkboard = @args.key?("show_on_chalkboard") ? @args["show_on_chalkboard"] : true

    student =
      if student_id == current_teacher.id
        current_teacher
      else
        current_teacher.students.find_by(id: student_id)
      end
    raise ToolExecutionError, "Student not found" unless student

    teacher = current_teacher
    today_str = Time.current.strftime("%B %d, %Y")
    journal_link = Rails.application.routes.url_helpers.admin_student_path(student, active_tab: "journal_timeline")

    pending_observation_count = student.observations.pending.count

    # Recent context (always included)
    lesson_reports = student.student_reports
                          .lesson_reports
                          .status_completed
                          .where(teacher: teacher)
                          .order(created_at: :desc)
                          .limit(6)

    course_reports = student.student_reports
                          .course_reports
                          .status_completed
                          .where(teacher: teacher)
                          .order(created_at: :desc)
                          .limit(3)

    profile_report = student.student_reports
                            .profile_reports
                            .status_completed
                            .where(teacher: teacher)
                            .order(created_at: :desc)
                            .first

    memories_recent = student.memories.order(created_at: :desc).limit(8)
    observations_recent = student.observations.for_context.limit(12)
    feedback_recent = student.student_feedbacks.includes(:lesson_progress).order(created_at: :desc).limit(5)

    # Courses snapshot (in-progress only)
    enrollments_in_progress = student.enrollments.in_progress.includes(:course).order(created_at: :desc)

    # Focus-based semantic retrieval (additive; never replaces recent context)
    focus_mode = nil
    focus_memories = []
    focus_observations = []
    if focus.present?
      if AppSetting.embeddings_configured?
        vector = EmbeddingService.get(focus)
        if vector
          focus_mode = "embeddings"
          begin
            focus_memories = Memory.nearest_neighbors(:embedding, vector, distance: "cosine")
                                   .where(student: student)
                                   .limit(5)
            focus_observations = Observation.nearest_neighbors(:embedding, vector, distance: "cosine")
                                            .where(student: student)
                                            .approved
                                            .limit(5)
          rescue StandardError => e
            Rails.logger.error "Get_Student_Profile focus retrieval failed: #{e.message}"
            focus_mode = "keyword"
          end
        else
          focus_mode = "keyword"
        end
      else
        focus_mode = "keyword"
      end

      if focus_mode == "keyword"
        q = focus.downcase
        focus_memories = memories_recent.select { |m| m.body.to_s.downcase.include?(q) }.first(5)
        focus_observations = observations_recent.select { |o| o.content.to_s.downcase.include?(q) }.first(5)
      end
    end

    # Deduplicate focus items against recent items (and within themselves)
    recent_memory_ids = memories_recent.map(&:id).to_set
    recent_observation_ids = observations_recent.map(&:id).to_set
    focus_memories = focus_memories.uniq { |m| m.id }.reject { |m| recent_memory_ids.include?(m.id) }
    focus_observations = focus_observations.uniq { |o| o.id }.reject { |o| recent_observation_ids.include?(o.id) }

    # Activity signal (best-effort)
    last_message_at = Message.joins(:conversation)
                             .where(conversations: { user_id: student.id })
                             .order(created_at: :desc)
                             .limit(1)
                             .pluck(:created_at)
                             .first
    last_activity_at = [ last_message_at, lesson_reports.first&.created_at, course_reports.first&.created_at, feedback_recent.first&.created_at ].compact.max

    profile_markdown = ApplicationController.render(
      partial: "students/student_profile",
      formats: [ :md ],
      locals: {
        student: student,
        teacher: teacher,
        today_str: today_str,
        journal_link: journal_link,
        pending_observation_count: pending_observation_count,
        enrollments_in_progress: enrollments_in_progress,
        lesson_reports: lesson_reports,
        course_reports: course_reports,
        profile_report: profile_report,
        memories_recent: memories_recent,
        observations_recent: observations_recent,
        feedback_recent: feedback_recent,
        focus: focus,
        focus_mode: focus_mode,
        focus_memories: focus_memories,
        focus_observations: focus_observations,
        last_activity_at: last_activity_at
      }
    ).to_s

    if show_on_chalkboard
      broadcast_chalkboard_student_profile(profile_markdown)
      create_tool_message(profile_markdown + "\n\n(Also displayed on chalkboard.)\n")
    else
      create_tool_message(profile_markdown)
    end
  end

  def execute_create_course
    # Teacher-only tool
    title = @args["title"]
    summary = @args["summary"]
    grade = @args["grade_level"]

    course = current_teacher.taught_courses.new(title: title, summary: summary, grade_level: grade)

    if course.save
      create_tool_message(JSON.pretty_generate({ status: "ok", course: course.as_json(only: [ :id, :title, :summary, :grade_level, :status ]) }))
    else
      raise ToolExecutionError, "Validation failed: #{course.errors.full_messages.join(', ')}"
    end
  end

  def execute_update_course
    # Teacher-only tool
    course_id = @args["course_id"].to_i
    course = current_teacher.taught_courses.find_by(id: course_id)
    raise ToolExecutionError, "Course not found" unless course

    Course.transaction do
      # Update basic course fields if provided
      course.title = @args["title"] if @args["title"].present?
      course.summary = @args["summary"] if @args["summary"].present?
      course.grade_level = @args["grade_level"] if @args["grade_level"].present?

      # If an outline is provided, expect an array of { "topic": "...", "description": "..." }
      if @args.key?("outline")
        outline_items = @args["outline"]
        unless outline_items.is_a?(Array)
          raise ToolExecutionError, "outline must be an array"
        end

        begin
          course.outline = outline_items.map do |it|
            topic = it["topic"]
            desc = it["description"]
            if topic.blank? || desc.blank?
              raise ToolExecutionError, "Each outline item must include non-empty 'topic' and 'description'"
            end
            { topic => desc }
          end
        rescue => e
          raise ToolExecutionError, e.message
        end
      end

      course.save!
      create_tool_message(JSON.pretty_generate({ status: "ok", course: course.for_llm }))
    end
  end

  def execute_update_lesson_plan
    # Teacher-only tool
    lesson_id = @args["lesson_id"].to_i
    lesson = Lesson.find_by(id: lesson_id)
    raise ToolExecutionError, "Lesson not found" unless lesson
    raise ToolExecutionError, "Permission denied" unless lesson.course.teacher == current_teacher

    Lesson.transaction do
      # Build/find lesson plan
      lp = lesson.lesson_plan || lesson.build_lesson_plan(status: "draft")

      # Expect flattened, explicit arrays:
      # lesson_plan_content: [{ "type": "...", "details": "..." }, ...] (OPTIONAL)
      if @args.key?("lesson_plan_content")
        content_items = @args["lesson_plan_content"]
        unless content_items.is_a?(Array)
          raise ToolExecutionError, "content must be an array"
        end

        # Convert to persisted JSONB shape: [{ "Type" => "Details" }, ...]
        begin
          lp.content = content_items.map do |i|
            t = i["type"]
            d = i["details"]
            if t.blank? || d.blank?
              raise ToolExecutionError, "Each content item must include non-empty 'type' and 'details'"
            end
            { t => d }
          end
        rescue => e
          raise ToolExecutionError, e.message
        end
      end

      # Suggested resources (optional): explicit array of { type, description }
      if @args.key?("suggested_resources")
        suggested_items = @args["suggested_resources"]
        if suggested_items.present?
          unless suggested_items.is_a?(Array)
            raise ToolExecutionError, "suggested_resources must be an array when provided"
          end
          begin
            lp.suggested_resources = suggested_items.map do |i|
              t = i["type"]
              desc = i["description"]
              if t.blank? || desc.blank?
                raise ToolExecutionError, "Each suggested resource must include non-empty 'type' and 'description'"
              end
              { t => desc }
            end
          rescue => e
            raise ToolExecutionError, e.message
          end
        else
          # Preserve or reset to [] explicitly if nil/empty passed
          lp.suggested_resources ||= []
        end
      end

      # Optional lesson plan fields
      lp.status = @args["lesson_plan_status"] if @args.key?("lesson_plan_status")
      lp.audio = @args["audio"] if @args.key?("audio")
      lp.chalkboard_enabled = !!@args["chalkboard_enabled"] if @args.key?("chalkboard_enabled")

      lp.save!

      create_tool_message(JSON.pretty_generate({
        status: "ok",
        lesson: { id: lesson.id, title: lesson.title, goals: lesson.goals, approx_duration_min: lesson.approx_duration_min },
        lesson_plan: {
          id: lp.id,
          status: lp.status,
          content: lp.content,
          suggested_resources: lp.suggested_resources,
          audio: lp.audio,
          chalkboard_enabled: lp.chalkboard_enabled
        }
      }))
    end

    # Broadcast the updated lesson to the chalkboard by default
    broadcast_chalkboard_lesson(lesson)
  end

  # ---- Generator tools (blocking) ----
  def execute_generate_course_outline
    # Teacher-only tool
    course_id = @args["course_id"].to_i
    course = current_teacher.taught_courses.find_by(id: course_id)
    raise ToolExecutionError, "Course not found" unless course

    action = @args["action"].to_s.strip.presence || "generate_outline"

    case action
    when "generate_outline"
      begin
        GenerateCourseOutlineJob.perform_now(course, current_teacher)
        course.reload
        create_tool_message(JSON.pretty_generate(course.for_llm))
      rescue StandardError => e
        Rails.logger.error "GenerateCourseOutlineJob error: #{e.message}"
        raise ToolExecutionError, "Failed to generate course outline: #{e.message}"
      end
    when "research_outline"
      begin
        enqueue_result = enqueue_course_outline_research(course: course)
        broadcast_chalkboard_outline_research_queued(course)
        course.reload
        create_tool_message(JSON.pretty_generate({
          status: "queued",
          action: action,
          message: enqueue_result[:message],
          course_id: course.id,
          outline_research_stage: course.outline_research_stage,
          note: "Outline research runs asynchronously. The teacher will be notified in chalkboard when guidance input is ready."
        }))
      rescue StandardError => e
        raise e if e.is_a?(ToolExecutionError)

        Rails.logger.error "GenerateCourseOutline research_outline error: #{e.message}"
        raise ToolExecutionError, "Failed to research course outline: #{e.message}"
      end
    when "generate_and_research"
      begin
        GenerateCourseOutlineJob.perform_now(course, current_teacher)
      rescue StandardError => e
        Rails.logger.error "GenerateCourseOutlineJob error: #{e.message}"
        raise ToolExecutionError, "Failed to generate course outline: #{e.message}"
      end

      begin
        enqueue_result = enqueue_course_outline_research(course: course)
        broadcast_chalkboard_outline_research_queued(course)
        course.reload
        create_tool_message(JSON.pretty_generate({
          status: "ok",
          action: action,
          message: "Generated outline and queued deep research.",
          generation_status: "completed",
          research_status: "queued",
          research_message: enqueue_result[:message],
          course_id: course.id,
          outline_research_stage: course.outline_research_stage,
          note: "Outline research runs asynchronously. The teacher will be notified in chalkboard when guidance input is ready.",
          course: course.for_llm
        }))
      rescue StandardError => e
        raise e if e.is_a?(ToolExecutionError)

        Rails.logger.error "GenerateCourseOutline generate_and_research enqueue error: #{e.message}"
        raise ToolExecutionError, "Outline was generated, but failed to queue research: #{e.message}"
      end
    else
      raise ToolExecutionError, "Unknown Generate_Course_Outline action: #{action.inspect}"
    end
  end

  def execute_edit_course_lessons
    # Teacher-only tool
    course_id = @args["course_id"].to_i
    course = current_teacher.taught_courses.find_by(id: course_id)
    raise ToolExecutionError, "Course not found" unless course

    Course.transaction do
      # 0. Delete Lessons
      if @args["lessons_to_delete"].present?
        @args["lessons_to_delete"].each do |l_id|
          lesson = course.lessons.find_by(id: l_id)
          raise ToolExecutionError, "Lesson #{l_id} not found in course #{course_id}" unless lesson

          # Check for lesson plan
          if lesson.lesson_plan.present?
            raise ToolExecutionError, "Cannot delete lesson #{l_id} ('#{lesson.title}') because it has a lesson plan."
          end

          lesson.destroy!
        end
        # Reload course association to ensure deleted lessons are gone from memory for subsequent steps
        course.lessons.reload
      end

      # 1. Update Lessons
      if @args["lessons_to_update"].present?
        @args["lessons_to_update"].each do |item|
          l_id = item["id"].to_i
          lesson = course.lessons.find_by(id: l_id)
          raise ToolExecutionError, "Lesson #{l_id} not found in course #{course_id}" unless lesson

          lesson.title = item["title"] if item["title"].present?
          lesson.goals = item["goals"] if item["goals"].present?
          lesson.approx_duration_min = item["approx_duration_min"].to_i if item["approx_duration_min"].present?
          lesson.save!
        end
      end

      # 2. Reorder Lessons
      if @args["lessons_order"].present?
        order_list = @args["lessons_order"]
        # Validation: ensure strict 1-to-1 match of IDs
        input_ids = order_list.map { |x| x["id"].to_i }.sort
        existing_ids = course.lessons.pluck(:id).sort

        unless input_ids == existing_ids
          raise ToolExecutionError, "lessons_order must contain exactly all lesson IDs for this course. Missing: #{existing_ids - input_ids}, Extras: #{input_ids - existing_ids}"
        end

        # We should also validate positions are 1..N
        sorted_orders = order_list.sort_by { |x| x["position"].to_i }
        expected_positions = (1..existing_ids.count).to_a
        given_positions = sorted_orders.map { |x| x["position"].to_i }
        unless given_positions == expected_positions
          raise ToolExecutionError, "lessons_order positions must be a contiguous sequence from 1 to N."
        end

        # Apply updates using acts_as_list's insert_at to handle shuffling safely
        sorted_orders.each do |item|
          l_id = item["id"].to_i
          l = course.lessons.find(l_id)
          l.insert_at(item["position"].to_i)
        end
      end
    end

    course.reload
    create_tool_message(JSON.pretty_generate(course.for_llm))
  end

  def execute_generate_course_lessons
    # Teacher-only tool
    course_id = @args["course_id"].to_i
    course = current_teacher.taught_courses.find_by(id: course_id)
    raise ToolExecutionError, "Course not found" unless course

    replace = !!@args["replace_existing_lessons"]

    begin
      # Run the generation job synchronously; caller is expected to wait for completion
      GenerateCourseLessonsJob.perform_now(course, current_teacher, replace_existing_lessons: replace)
      course.reload
      create_tool_message(JSON.pretty_generate(course.for_llm))
    rescue StandardError => e
      Rails.logger.error "GenerateCourseLessonsJob error: #{e.message}"
      raise ToolExecutionError, "Failed to generate lessons: #{e.message}"
    end
  end

  def execute_generate_lesson_plan
    lesson_id = @args["lesson_id"].to_i
    lesson = Lesson.find_by(id: lesson_id)
    raise ToolExecutionError, "Lesson not found" unless lesson
    raise ToolExecutionError, "Permission denied" unless lesson.course.teacher == current_teacher

    lp = lesson.lesson_plan || lesson.build_lesson_plan(status: "draft")
    lp.save! if lp.new_record?

    action = @args["action"].to_s.strip
    raise ToolExecutionError, "Missing required parameter: action" if action.blank?

    case action
    when "generate_content"
      begin
        GenerateLessonPlanContentJob.perform_now(lp, current_teacher)
        lesson.reload
        create_tool_message(JSON.pretty_generate(lesson.for_llm))
      rescue StandardError => e
        Rails.logger.error "GenerateLessonPlanContentJob error: #{e.message}"
        raise ToolExecutionError, "Failed to generate lesson plan content: #{e.message}"
      end
    when "propose_resources_async"
      enqueue_result = LessonPlanAsyncGenerationService.new(
        lesson_plan: lp,
        current_user: current_teacher,
        source: "teacher_chat_tool"
      ).enqueue_propose_resources
      raise ToolExecutionError, enqueue_result[:message] unless enqueue_result[:ok]

      create_tool_message(JSON.pretty_generate({
        status: "queued",
        action: action,
        message: enqueue_result[:message],
        lesson_id: lesson.id,
        lesson_plan_id: lp.id,
        generation_stage: enqueue_result[:stage],
        next_step: "Use Get_Lesson_Details to check generation_stage until it reaches completed or failed."
      }))
    when "generate_content_and_propose_resources_async"
      enqueue_result = LessonPlanAsyncGenerationService.new(
        lesson_plan: lp,
        current_user: current_teacher,
        source: "teacher_chat_tool"
      ).enqueue_generate_content(propose_resources: true)
      raise ToolExecutionError, enqueue_result[:message] unless enqueue_result[:ok]

      create_tool_message(JSON.pretty_generate({
        status: "queued",
        action: action,
        message: enqueue_result[:message],
        lesson_id: lesson.id,
        lesson_plan_id: lp.id,
        generation_stage: enqueue_result[:stage],
        next_step: "Use Get_Lesson_Details to check generation_stage until it reaches completed or failed."
      }))
    else
      raise ToolExecutionError, "Unknown Generate_Lesson_Plan action: #{action.inspect}"
    end
  end

  def enqueue_course_outline_research(course:)
    result = CourseOutlineResearchAsyncService.new(
      course: course,
      current_user: current_teacher,
      source: "teacher_chat_tool",
      conversation_id: @conversation.id
    ).enqueue_start
    raise ToolExecutionError, result[:message] unless result[:ok]

    result
  end

  def broadcast_chalkboard_outline_research_queued(course)
    broadcast_chalkboard_push_tab(
      tab_title: "Outline Research",
      kind: "outline_research",
      partial: "admin/courses/chalkboard_research_queued",
      locals: { course: course }
    )
  end

  def execute_generate_image
    prompt = @args["prompt"]
    raise ToolExecutionError, "Missing required parameter: prompt" unless prompt.present?

    # Perform job synchronously.
    GenerateImageJob.perform_now(
      conversation_id: @conversation.id,
      user_id: @user.id,
      prompt: prompt,
      tool_call_id: @tool_call_id
    )
    # Tool message is created by the job.
  rescue StandardError => e
    raise ToolExecutionError, "Image generation failed: #{e.message}"
  end

  # ---- Applets tools ----
  def execute_applet
    # Legacy tool name. Keep for backward compatibility.
    execute_applet_actions(allowed_actions: %w[list get upsert save_as_resource run_on_chalkboard])
  end

  def execute_manage_applets
    execute_applet_actions(allowed_actions: %w[list get upsert save_as_resource run_on_chalkboard])
  end

  def execute_view_applets
    execute_applet_actions(allowed_actions: %w[list get run_on_chalkboard])
  end

  def execute_applet_actions(allowed_actions:)
    action = @args["action"].to_s

    unless allowed_actions.include?(action)
      raise ToolExecutionError, "Unknown or disallowed Applet action: #{action.inspect}"
    end
    if %w[get run_on_chalkboard save_as_resource].include?(action) && @args["applet_id"].blank?
      raise ToolExecutionError, "Missing required parameter: applet_id"
    end
    if action == "upsert" && @args["applet_id"].present? && !(@args.key?("title") || @args.key?("code"))
      raise ToolExecutionError, "Missing required parameter: title or code"
    end

    case action
    when "list"
      applet_list
    when "get"
      applet_get
    when "upsert"
      applet_upsert
    when "save_as_resource"
      applet_save_as_resource
    when "run_on_chalkboard"
      applet_run_on_chalkboard
    else
      raise ToolExecutionError, "Unknown Applet action: #{action.inspect}"
    end
  end

  def applet_list
    scope = applet_scope_for_user
    # If this is a lesson, only show applets that are in the lesson
    if @conversation&.lesson_progress.present?
      lesson_resource_ids = @conversation.lesson_progress.resources.select(:id)
      scope = scope.where(resource_id: lesson_resource_ids)
    end
    applets = scope.order(created_at: :desc).limit(100)
    payload = applets.map { |a| { id: a.id, title: a.title, created_at: a.created_at } }
    create_tool_message(JSON.pretty_generate(payload))
  end

  def applet_get
    applet_id = @args["applet_id"].to_i
    applet = applet_scope_for_user.find_by(id: applet_id)
    raise ToolExecutionError, "Applet not found" unless applet
    enforce_lesson_applet_scope!(applet)
    payload = { id: applet.id, title: applet.title, code: applet.code, warning: "If copying this code into an executable markdown block, there is no need to add escaping. Do not add extra backslashes." }
    create_tool_message(payload) # Avoid using JSON to avoid LLM syntax issues due to escaping
  end

  def applet_upsert
    if @args.key?("code") && @args["code"].present?
      syntax_check = NodeJsSyntaxChecker.check(@args["code"])
      unless syntax_check[:valid]
        raise ToolExecutionError, "JavaScript syntax errors: #{syntax_check[:errors].join('; ')}"
      end
    end

    if @args["applet_id"].present?  # Update existing applet
      applet_id = @args["applet_id"].to_i
      applet = applet_scope_for_user.find_by(id: applet_id)
      raise ToolExecutionError, "Applet not found" unless applet

      if @args.key?("code") && @args["code"].present?
        applet.code = @args["code"]
      end

      if @args.key?("title")
        applet.title = @args["title"]
      end

      if applet.changed?
        applet.save!
        action = "updated"
      else
        action = "no changes"
      end
    else # Create new applet
      raise ToolExecutionError, "Missing required parameter: title" unless @args["title"].present?
      raise ToolExecutionError, "Missing required parameter: code" unless @args["code"].present?

      applet = current_teacher.applets.new(title: @args["title"], code: @args["code"])
      applet.save!
      action = "created"
    end

    create_tool_message({
      status: "ok",
      action: action,
      applet: {
        id: applet.id,
        title: applet.title,
        code: applet.code,
        created_at: applet.created_at,
        updated_at: applet.updated_at
      }
    })
  end

  def applet_save_as_resource
    applet_id = @args["applet_id"].to_i
    lesson_id = @args["lesson_id"]

    # Find the applet under teacher
    applet = applet_scope_for_user.find_by(id: applet_id)
    raise ToolExecutionError, "Applet not found" unless applet

    # Verify lesson_plan if provided
    lesson_plan = nil
    if lesson_id.present?
      lesson = Lesson.find_by(id: lesson_id)
      raise ToolExecutionError, "Lesson not found" unless lesson
      raise ToolExecutionError, "Permission denied, lesson does not belong to the current user" unless lesson.teacher == current_teacher
      lesson_plan = lesson.lesson_plan || lesson.build_lesson_plan(status: "draft")
    end

    # Reuse existing resource if the applet already has one
    if applet.resource.present?
      resource = applet.resource

      # Ensure metadata is consistent
      resource.category = "Applet"
      resource.description = "#{applet.title}" if resource.description.blank?
      resource.save! if resource.changed?
    else
      # Create resource
      resource = Resource.create!(
        teacher: current_teacher,
        category: "Applet",
        description: "#{applet.title}",
        approved: false,
        applet: applet
      )
    end

    # Link to lesson plan if provided
    if lesson_plan
      lesson_plan.save! if lesson_plan.new_record?
      unless lesson_plan.resources.exists?(id: resource.id)
        lesson_plan.resources << resource
      end
    end

    payload = {
      status: "ok",
      resource: { id: resource.id, category: resource.category, description: resource.description },
      lesson_id: lesson_plan&.id
    }
    create_tool_message(JSON.pretty_generate(payload))
  end

  def applet_run_on_chalkboard
    applet_id = @args["applet_id"].to_i
    applet = applet_scope_for_user.find_by(id: applet_id)
    raise ToolExecutionError, "Applet not found" unless applet
    enforce_lesson_applet_scope!(applet)

    run_applet_on_chalkboard(applet: applet, source: "linked", key: "linked_#{applet.id}")

    Rails.logger.debug("Chalkboard applet registered: #{applet.title}")
    create_tool_message("Applet is available in the chalkboard Applets tab: #{applet.title}")
  end

  def enforce_lesson_applet_scope!(applet)
    return unless @conversation&.lesson_progress.present?
    # Ensures that applet is linked to the current lesson
    return if applet.resource_id.present? && @conversation.lesson_progress.resources.exists?(id: applet.resource_id)

    raise ToolExecutionError, "Applet not available for this lesson"
  end

  def execute_chalkboard_url_payload(raw_url, tab_title:)
    url = raw_url.to_s.strip
    begin
      embed_result = UrlEmbeddabilityService.check(url: url)
    rescue UrlEmbeddabilityService::ValidationError
      raise ToolExecutionError, "Invalid or unsafe URL provided"
    end

    case embed_result[:status].to_s
    when "embeddable"
      Rails.logger.debug "Broadcasting embeddable URL to chalkboard #{url}"
      broadcast_chalkboard_push_tab(
        tab_title: tab_title,
        kind: "url",
        partial: "shared/chalkboard_iframe",
        locals: { url: url }
      )
      create_tool_message("Chalkboard URL opened in new tab: #{url}\nBackup link: [Open link](#{url})")
    when "blocked_xfo", "blocked_csp"
      reason = embed_result[:reason].to_s
      Rails.logger.debug "Broadcasting fallback URL tab to chalkboard #{url} reason=#{reason}"
      broadcast_chalkboard_push_tab(
        tab_title: tab_title,
        kind: "url",
        partial: "shared/chalkboard_link_fallback",
        locals: { url: url, reason: reason }
      )
      create_tool_message("This site blocks iframe embedding. A direct-link chalkboard tab was opened.\nOpen link: [#{url}](#{url})")
    else
      Rails.logger.debug "Broadcasting URL with unknown embeddability to chalkboard #{url}"
      broadcast_chalkboard_push_tab(
        tab_title: tab_title,
        kind: "url",
        partial: "shared/chalkboard_iframe",
        locals: { url: url }
      )
      create_tool_message(
        "Chalkboard URL was changed to: #{url}. Embeddability check was inconclusive, so iframe display may fail.\n" \
        "Backup link: [Open link](#{url})"
      )
    end
  end

  def execute_chalkboard_resource_payload(resource)
    if resource.file.attached?
      execute_chalkboard_file_payload(resource)
    elsif resource.uri.present?
      execute_chalkboard_url_payload(resource.uri, tab_title: "Resource Link")
    elsif resource.content.present?
      execute_chalkboard_text_payload(resource)
    elsif resource.applet.present?
      run_applet_on_chalkboard(applet: resource.applet, source: "resource", key: "resource_#{resource.id}")
      create_tool_message("Applet is available in the chalkboard Applets tab: #{resource.applet.title}")
    else
      raise ToolExecutionError, "Resource does not have a displayable payload"
    end
  end

  def execute_chalkboard_file_payload(resource)
    url = Rails.application.routes.url_helpers.rails_blob_path(resource.file, disposition: "inline", only_path: true)
    file_type = resource.file.content_type.to_s
    filename = resource.file.filename.to_s

    broadcast_chalkboard_push_tab(
      tab_title: "File: #{filename}",
      kind: "file",
      partial: "shared/chalkboard_file",
      locals: { url: url, file_type: file_type, filename: filename }
    )

    Rails.logger.debug("Chalkboard updated with file: #{filename} (#{file_type})")
    create_tool_message("Chalkboard updated with file: #{filename} (#{file_type}) (opened in a new chalkboard tab)")
  end

  def execute_chalkboard_text_payload(resource)
    name = resource.category.to_s.strip.presence || "Text Resource"
    description = resource.description.to_s.strip.presence || "No description."
    broadcast_chalkboard_push_tab(
      tab_title: description,
      kind: "resource_text",
      partial: "shared/chalkboard_text_resource",
      locals: {
        resource_name: name,
        resource_description: description,
        text_content: resource.content.to_s
      }
    )
    create_tool_message("Chalkboard updated with text resource: #{description} (opened in a new chalkboard tab)")
  end

  def find_and_authorize_chalkboard_resource!(resource_id)
    resource = Resource.find_by(id: resource_id)
    raise ToolExecutionError, "Resource not found with ID: #{resource_id}" unless resource

    authorize_chalkboard_resource_access!(resource)
    resource
  end

  def authorize_chalkboard_resource_access!(resource)
    return unless resource.teacher.present?

    if @user.role_student?
      unless @user.teacher == resource.teacher
        raise ToolExecutionError, "Permission denied: resource does not belong to your teacher"
      end
    elsif @user != resource.teacher
      raise ToolExecutionError, "Permission denied: resource does not belong to you"
    end
  end

  def enforce_lesson_resource_scope!(resource)
    return unless @conversation&.lesson_progress.present?
    return if @conversation.lesson_progress.resources.exists?(id: resource.id)

    raise ToolExecutionError, "Resource not available for this lesson"
  end

  def run_applet_on_chalkboard(applet:, source:, key:)
    run_url = Rails.application.routes.url_helpers.run_applet_path(applet)
    broadcast_chalkboard_event(
      event_type: "register_applet",
      source: source,
      key: key,
      applet_id: applet.id,
      title: applet.title.to_s,
      launch_url: run_url,
      embed_src: run_url,
      embed_srcdoc: nil,
      shareable: true,
      share_url: run_url,
      focus: true,
      auto_open_in_board: true
    )
  end

  def execute_delegate_to_frontier_llm
    prompt = @args["prompt"]
    raise ToolExecutionError, "Missing required parameter: prompt" unless prompt.present?

    begin
      # Run the delegation job synchronously; caller is expected to wait for completion
      result = DelegateToFrontierLlmJob.perform_now(current_teacher, prompt, source: "tool_call")
      create_tool_message(<<~CONTENT
        Frontier LLM response complete.
        This response has not yet been shown to the user, executed, or otherwise acted upon; this remains your decision.
        Executable markdown blocks are not executed yet, since tool messages are not shown to the user.
        Response:
        #{result}
      CONTENT
      )
    rescue StandardError => e
      Rails.logger.error "DelegateToFrontierLlmJob error: #{e.message}"
      raise ToolExecutionError, "Failed to delegate to reasoning LLM: #{e.message}"
    end
  end

  def create_tool_message(content)
    Message.create!(
      conversation: @conversation,
      role: "tool",
      content: content,
      tool_call_id: @tool_call_id
    )
  end

  def broadcast_error(message)
    Turbo::StreamsChannel.broadcast_append_to(
      "#{dom_id(@conversation)}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
  end

  def broadcast_chalkboard_lesson(lesson)
    broadcast_chalkboard_push_tab(
      tab_title: "Lesson",
      kind: "lesson",
      partial: "lessons/chalkboard_markdown",
      locals: { lesson: lesson }
    )
  end

  def broadcast_chalkboard_student_profile(profile_markdown)
    broadcast_chalkboard_push_tab(
      tab_title: "Student Profile",
      kind: "profile",
      partial: "shared/chalkboard_student_profile",
      locals: { profile_markdown: profile_markdown }
    )
  end

  def broadcast_chalkboard_push_tab(tab_title:, kind:, partial:, locals:)
    content_html = ApplicationController.render(partial: partial, locals: locals)
    broadcast_chalkboard_event(
      event_type: "open_push_tab",
      tab_id: "#{kind}_#{SecureRandom.hex(6)}",
      tab_title: tab_title,
      kind: kind,
      content_html: content_html
    )
  end

  def broadcast_chalkboard_event(payload)
    Turbo::StreamsChannel.broadcast_append_to(
      "conversation_#{@conversation.id}",
      target: "chalkboard_tab_inbox",
      partial: "shared/chalkboard_tab_event",
      locals: { payload: payload }
    )
  end

  def broadcast_lesson_completed
    Turbo::StreamsChannel.broadcast_before_later_to(
      "#{dom_id(@conversation)}",
      target: "#{dom_id(@conversation)}_accent",
      partial: "student/lessons/lesson_completed"
    )
  end
end
