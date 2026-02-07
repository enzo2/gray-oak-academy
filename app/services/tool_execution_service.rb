require "json/repair"
require "resolv"
require "ipaddr"
require "set"

class ToolExecutionService
  class ToolExecutionError < StandardError; end
  include ActionView::RecordIdentifier

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
    @user = conversation.user
  end

  def execute_tool_call(tool_call)
    @tool_call_id = tool_call[:id]

    begin
      # Find the tool by name (case-insensitive to handle LLM capitalization errors)
      tool = Tool.where("name ILIKE ?", tool_call[:name]).first
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
        rescue JSON::ParserError
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

  def valid_chalkboard_url?(url)
    return false if url.nil? || url.strip.empty?
    s = url.strip
    # Reject unsafe schemes
    down = s.downcase
    return false if down.start_with?("javascript:", "data:")
    begin
      uri = URI.parse(s)
    rescue StandardError => e
      Rails.logger.debug "Invalid URL parse: #{e.message}"
      return false
    end
    scheme = uri.scheme&.downcase
    return false unless scheme == "https"
    host = uri.host
    return false unless host

    # Resolve host to IP addresses and ensure none are private/reserved
    begin
      # If the host is an IP literal (e.g. "192.0.2.1" or "2001:db8::1"), validate it directly first.
      ip_literal = begin
        IPAddr.new(host)
      rescue StandardError
        nil
      end

      # Expanded set of private/reserved ranges to reject
      private_ranges = [
        IPAddr.new("0.0.0.0/8"),
        IPAddr.new("10.0.0.0/8"),
        IPAddr.new("100.64.0.0/10"),
        IPAddr.new("127.0.0.0/8"),
        IPAddr.new("169.254.0.0/16"),
        IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.0.0.0/24"),
        IPAddr.new("192.0.2.0/24"),
        IPAddr.new("192.88.99.0/24"),
        IPAddr.new("192.168.0.0/16"),
        IPAddr.new("198.18.0.0/15"),
        IPAddr.new("198.51.100.0/24"),
        IPAddr.new("203.0.113.0/24"),
        IPAddr.new("224.0.0.0/4"),
        IPAddr.new("240.0.0.0/4"),
        IPAddr.new("::/128"),      # unspecified
        IPAddr.new("::1/128"),     # loopback
        IPAddr.new("fe80::/10"),   # link-local
        IPAddr.new("fc00::/7")     # unique local addresses
      ]

      if ip_literal
        # Reject if the literal is in a private/reserved range
        return false if private_ranges.any? { |r| r.include?(ip_literal) }
        # If it's a public IP literal, accept (no DNS lookup needed)
        return true
      end

      addrs = Resolv.getaddresses(host)
      if addrs.empty?
        Rails.logger.debug "No addresses resolved for host: #{host}"
        return false
      end

      addrs.each do |a|
        ip = IPAddr.new(a) rescue nil
        next unless ip
        return false if private_ranges.any? { |r| r.include?(ip) }
      end
    rescue => e
      Rails.logger.debug "Host resolution error for chalkboard URL: #{e.class}: #{e.message}"
      return false
    end

    true
  end

  # -- Tool execution methods --

  def execute_chalkboard_url
    url = @args["url"].to_s.strip
    unless valid_chalkboard_url?(url)
      raise ToolExecutionError, "Invalid or unsafe URL provided"
    end

    Rails.logger.debug "Broadcasting URL to chalkboard #{url}"

    # Broadcast chalkboard update to the conversation
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{@conversation.id}",
      target: "chalkboard",
      partial: "shared/chalkboard_iframe",
      locals: { url: url }
    )
    create_tool_message("Chalkboard URL was changed to: #{url}")
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

  def execute_chalkboard_file
    resource_id = @args["resource_id"]
    # Find the resource
    resource = Resource.find_by(id: resource_id)
    raise ToolExecutionError, "Resource not found with ID: #{resource_id}" unless resource

    # Ensure the resource is available for the user, unless it's public
    if resource.teacher.present?
      if @user.role_student?
        # Students can only access resources belonging to their teacher
        unless @user.teacher == resource.teacher
          raise ToolExecutionError, "Permission denied: resource does not belong to your teacher"
        end
      else
        # Teachers can only access their own resources
        unless @user == resource.teacher
          raise ToolExecutionError, "Permission denied: resource does not belong to you"
        end
      end
    end

    # Check if the resource has a file attached
    raise ToolExecutionError, "Resource does not have a file attached" unless resource.file.attached?

    # Get the file URL
    url = Rails.application.routes.url_helpers.rails_blob_path(resource.file, disposition: "inline", only_path: true)

    # Get the file type and filename
    file_type = resource.file.content_type
    filename = resource.file.filename.to_s

    # Broadcast chalkboard update with the file
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{@conversation.id}",
      target: "chalkboard",
      partial: "shared/chalkboard_file",
      locals: { url: url, file_type: file_type, filename: filename }
    )

    Rails.logger.debug("Chalkboard updated with file: #{filename} (#{file_type})")
    create_tool_message("Chalkboard updated with file: #{filename} (#{file_type})")
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
    journal_link = Rails.application.routes.url_helpers.admin_student_path(student, active_tab: "journal")

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
    observations_recent = student.observations.approved.order(created_at: :desc).limit(12)
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

    begin
      # Run the generation job synchronously; caller is expected to wait for completion
      GenerateCourseOutlineJob.perform_now(course, current_user = current_teacher)
      course.reload
      create_tool_message(JSON.pretty_generate(course.for_llm))
    rescue StandardError => e
      Rails.logger.error "GenerateCourseOutlineJob error: #{e.message}"
      raise ToolExecutionError, "Failed to generate course outline: #{e.message}"
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

    begin
      GenerateLessonPlanContentJob.perform_now(lp, current_teacher)
      lesson.reload
      create_tool_message(JSON.pretty_generate(lesson.for_llm))
    rescue StandardError => e
      Rails.logger.error "GenerateLessonPlanContentJob error: #{e.message}"
      raise ToolExecutionError, "Failed to generate lesson plan content: #{e.message}"
    end
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

    # Broadcast to chalkboard
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{@conversation.id}",
      target: "chalkboard",
      partial: "shared/chalkboard_applet",
      locals: { applet: applet }
    )

    Rails.logger.debug("Chalkboard updated with stored applet: #{applet.title}")
    create_tool_message("Chalkboard updated with stored applet: #{applet.title}")
  end

  def enforce_lesson_applet_scope!(applet)
    return unless @conversation&.lesson_progress.present?
    # Ensures that applet is linked to the current lesson
    return if applet.resource_id.present? && @conversation.lesson_progress.resources.exists?(id: applet.resource_id)

    raise ToolExecutionError, "Applet not available for this lesson"
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
    Turbo::StreamsChannel.broadcast_update_to(
      "#{dom_id(@conversation)}",
      target: "chalkboard",
      partial: "lessons/chalkboard_markdown",
      locals: { lesson: lesson }
    )
  end

  def broadcast_chalkboard_student_profile(profile_markdown)
    Turbo::StreamsChannel.broadcast_update_to(
      "#{dom_id(@conversation)}",
      target: "chalkboard",
      partial: "shared/chalkboard_student_profile",
      locals: { profile_markdown: profile_markdown }
    )
  end

  def broadcast_lesson_completed
    Turbo::StreamsChannel.broadcast_append_later_to(
      "#{dom_id(@conversation)}",
      target: "#{dom_id(@conversation)}",
      partial: "student/lessons/lesson_completed"
    )
  end
end
