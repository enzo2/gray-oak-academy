require "json/repair"
require "resolv"
require "ipaddr"

class ToolHandlerService
  class ToolExecutionError < StandardError; end
  include ActionView::RecordIdentifier

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
    @user = conversation.user
  end

  def execute_tool_call(tool_call)
    begin
      # Find the tool by name
      tool = Tool.find_by(name: tool_call[:name])
      raise ToolExecutionError, "Tool '#{tool_call[:name]}' not found" unless tool

      # Authorization: ensure caller is allowed to run this tool.
      if @user.role_student?
        # Tools only teachers should be allowed to call
        teacher_only_tools = %w[list_students generate_course_outline generate_course_lessons generate_lesson_plan create_course update_lesson]
        if teacher_only_tools.include?(tool.name)
          raise ToolExecutionError, "Permission denied: students are not allowed to call '#{tool.name}'"
        end
      end

      # Prevent runaway tool-call loops: disallow executing new tools if the conversation
      # already has too many consecutive tool messages without an intervening user message.
      if runaway_tool_call_limit_exceeded?(10)
        raise ToolExecutionError, "Permission denied: tool call limit reached for this conversation"
      end

      # Validate arguments against tool specifications
      @args = validate_and_parse_arguments(tool, tool_call[:arguments])
      @tool_call_id = tool_call[:id]

      # Execute the tool based on its name.
      # Ensure each tool method calls create_tool_message upon completion.
      case tool.name
      when "Chalkboard_URL"
        execute_chalkboard_url
      when "Chalkboard_File"
        execute_chalkboard_file
      when "Complete_Lesson"
        execute_complete_lesson
      when "python_sandbox"
        execute_python_code_executor
      when "list_students"
        execute_list_students
      when "list_courses"
        execute_list_courses
      when "get_course_details"
        execute_get_course_details
      when "get_lesson_details"
        execute_get_lesson_details
      when "get_student_reports"
        execute_get_student_reports
      when "generate_course_outline"
        execute_generate_course_outline
      when "generate_course_lessons"
        execute_generate_course_lessons
      when "generate_lesson_plan"
        execute_generate_lesson_plan
      when "create_course"
        execute_create_course
      when "update_lesson"
        execute_update_lesson
      else
        raise ToolExecutionError, "Tool '#{tool.name}' execution not implemented!"
      end
    rescue ToolExecutionError => e
      Rails.logger.error("ToolExecutionError: #{e.message}")
      # Notify the LLM of the error, not the user, since the LLM called the tool.
      create_tool_message("Tool execution resulted in error: #{e.message}")
    rescue => e
      Rails.logger.error("Unexpected error: #{e.message}")
      # Other errors are shown to the user.
      broadcast_error("Unexpected error: #{e.message}")
    end
  end

  private

  # Tolerant JSON parse + schema-aware coercion for common primitive types.
  def validate_and_parse_arguments(tool, arguments)
    # Parse JSON arguments
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
    end

    # Enforce strict_mode: reject unexpected parameters when strict_mode is set on the Tool
    if tool.specifications["strict_mode"]
      allowed_keys = (properties || {}).keys.map(&:to_s)
      extra_keys = parsed_arguments.keys.map(&:to_s) - allowed_keys
      unless extra_keys.empty?
        raise ToolExecutionError, "Unexpected parameters provided: #{extra_keys.join(', ')}"
      end
    end

    # Return the validated and parsed arguments
    parsed_arguments
  end

  # Security helpers

  def runaway_tool_call_limit_exceeded?(limit = 10)
    # Determine the timestamp of the most recent user message in the conversation.
    last_user = @conversation.messages.where(role: "user").order(created_at: :desc).limit(1).first

    if last_user
      # Count assistant/tool messages after the last user message.
      recent_count = @conversation.messages.where("created_at > ?", last_user.created_at)
                                          .where(role: [ "assistant", "tool" ])
                                          .count
    else
      # No user messages at all — count assistant/tool messages
      recent_count = @conversation.messages.order(created_at: :desc)
                                          .where(role: [ "assistant", "tool" ]).count
    end

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
      addrs = Resolv.getaddresses(host)
      if addrs.empty?
        Rails.logger.debug "No addresses resolved for host: #{host}"
        return false
      end
      private_ranges = [
        IPAddr.new("10.0.0.0/8"),
        IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.168.0.0/16"),
        IPAddr.new("127.0.0.0/8"),
        IPAddr.new("::1/128"),
        IPAddr.new("fc00::/7")
      ]
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

    # Create the student report
    StudentReport.create!(
      student: student,
      teacher: lesson.teacher,
      reportable: lesson_progress, # Associate the report with the LessonProgress, which will cause lesson_progress.completed? to return true
      progress_data: @args,
      author_type: :ai_generated,
      status: :completed
    )

    Rails.logger.debug("Lesson completed and student report generated for lesson: #{lesson.id}, student: #{student.id}")
    Rails.logger.debug("Report: #{@args}")

    # Broadcast completion message to the conversation
    broadcast_lesson_completed
    create_tool_message("Confirmation: Lesson completed and student report generated successfully. (Any further messages will not be reflected in the progress report.)")
  end

  def execute_chalkboard_file
    resource_id = @args["resource_id"]

    # No authorization check here; assume the LLM is only aware of the appropriate resources.

    # Find the resource
    resource = Resource.find_by(id: resource_id)
    raise ToolExecutionError, "Resource not found with ID: #{resource_id}" unless resource

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

  def execute_python_code_executor
    # May take a while, so broadcast a temporary message which will render a spinner
    # Will be removed once the actual response is broadcast
    broadcast_placeholder
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

  def current_teacher
    return @user if @user.role_teacher?
    return @user.teacher if @user.teacher.present?
    raise ToolExecutionError, "No teacher associated with current user"
  end

  def execute_list_students
    students = current_teacher.students.select(:id, :first_name, :last_name, :email)
    payload = students.map { |s| { id: s.id, name: s.name, email: s.email } }
    create_tool_message(JSON.pretty_generate(payload))
  end

  def execute_list_courses
    courses = current_teacher.taught_courses.select(:id, :title, :grade_level, :status)
    create_tool_message(JSON.pretty_generate(courses.as_json(only: [ :id, :title, :grade_level, :status ])))
  end

  def execute_get_course_details
    course_id = @args["course_id"].to_i
    course = current_teacher.taught_courses.includes(:lessons).find_by(id: course_id)
    raise ToolExecutionError, "Course not found" unless course

    create_tool_message(JSON.pretty_generate(course.for_llm))
  end

  def execute_get_lesson_details
    lesson_id = @args["lesson_id"].to_i
    lesson = Lesson.find_by(id: lesson_id)
    raise ToolExecutionError, "Lesson not found" unless lesson
    raise ToolExecutionError, "Permission denied" unless lesson.course.teacher == current_teacher

    create_tool_message(JSON.pretty_generate(lesson.for_llm))
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

    reports = student.student_reports.where(teacher: current_teacher).order(created_at: :desc)

    payload = {
      student: { id: student.id, name: student.name },
      report_counts: { lessons: reports.lesson_reports.count, courses: reports.course_reports.count },
      reports_markdown: reports.map(&:to_markdown).join("\n\n---\n\n")
    }
    create_tool_message(JSON.pretty_generate(payload))
  end

  def execute_create_course
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

  def execute_update_lesson
    lesson_id = @args["lesson_id"].to_i
    lesson = Lesson.find_by(id: lesson_id)
    raise ToolExecutionError, "Lesson not found" unless lesson
    raise ToolExecutionError, "Permission denied" unless lesson.course.teacher == current_teacher

    Lesson.transaction do
      lesson.title = @args["title"] if @args["title"].present?
      lesson.goals = @args["goals"] if @args["goals"].present?
      lesson.approx_duration_min = @args["approx_duration_min"].to_i if @args["approx_duration_min"].present?
      lesson.save!

      lp = lesson.lesson_plan || lesson.build_lesson_plan(teacher: current_teacher, status: "draft")
      plan_args = @args["lesson_plan"] || {}
      unless plan_args["content"].is_a?(Array)
        raise ToolExecutionError, "lesson_plan.content is required and must be an array"
      end

      lp.content = plan_args["content"]
      lp.suggested_resources = plan_args["suggested_resources"] if plan_args["suggested_resources"].is_a?(Array)
      lp.status = plan_args["status"] if plan_args["status"].present?
      lp.audio = plan_args["audio"] if plan_args["audio"].present?
      lp.chalkboard_enabled = !!plan_args["chalkboard_enabled"] if plan_args.key?("chalkboard_enabled")
      lp.teacher = current_teacher if lp.teacher_id.nil?
      lp.save!

      create_tool_message(JSON.pretty_generate({
        status: "ok",
        lesson: { id: lesson.id, title: lesson.title, goals: lesson.goals, approx_duration_min: lesson.approx_duration_min },
        lesson_plan: { id: lp.id, status: lp.status, content: lp.content, suggested_resources: lp.suggested_resources, audio: lp.audio, chalkboard_enabled: lp.chalkboard_enabled }
      }))
    end
  end

  # ---- Generator tools (blocking) ----
  def execute_generate_course_outline
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

  def execute_generate_course_lessons
    course_id = @args["course_id"].to_i
    course = current_teacher.taught_courses.find_by(id: course_id)
    raise ToolExecutionError, "Course not found" unless course

    begin
      # Run the generation job synchronously; caller is expected to wait for completion
      GenerateCourseLessonsJob.perform_now(course, current_teacher)
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

    lp = lesson.lesson_plan || lesson.build_lesson_plan(teacher: current_teacher, status: "draft")
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

  def broadcast_error(message)
    Turbo::StreamsChannel.broadcast_append_to(
      "#{dom_id(@conversation)}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
  end

  def broadcast_lesson_completed
    Turbo::StreamsChannel.broadcast_append_later_to(
      "#{dom_id(@conversation)}",
      target: "#{dom_id(@conversation)}",
      partial: "student/lessons/lesson_completed"
    )
  end

  def broadcast_placeholder
    Turbo::StreamsChannel.broadcast_append_to(
      "#{dom_id(@conversation)}",
      target: "#{dom_id(@conversation)}",
      partial: "messages/message",
      locals: { message: Message.new(role: :assistant, content: "") }
    )
  end

  def create_tool_message(content)
    Message.create!(
      conversation: @conversation,
      role: "tool",
      content: content,
      tool_call_id: @tool_call_id
    )
    # Allow the LLM to continue with the tool result.
    # Concurrency control is in place per conversation, so the original job will finish first (e.g. if multiple tools were called)
    GetLlmCompletionJob.perform_later(conversation: @conversation)
  end
end
