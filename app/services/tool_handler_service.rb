require "json/repair"

class ToolHandlerService
  class ToolExecutionError < StandardError; end  # Should be moved outside ToolHandlerService?

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
  end

  def execute_tool_call(tool_call)
    begin
      # Find the tool by name
      tool = Tool.find_by(name: tool_call[:name])
      raise ToolExecutionError, "Tool '#{tool_call[:name]}' not found" unless tool

      # Validate arguments against tool specifications
      args = validate_and_parse_arguments(tool, tool_call[:arguments])
      tool_call_id = tool_call[:id]

    # Execute the tool based on its name
    case tool.name
    when "Chalkboard_URL"
      execute_chalkboard_url(args)
    when "Chalkboard_File"
      execute_chalkboard_file(args)
    when "Complete_Lesson"
      execute_complete_lesson(args)
    when "python"
      execute_python_code_executor(args, tool_call_id)
    else
      raise ToolExecutionError, "Tool '#{tool.name}' execution not implemented"
    end
    rescue ToolExecutionError => e
      Rails.logger.error("ToolExecutionError: #{e.message}")
      broadcast_error(e.message, @conversation)
    end
  end

  private

  def validate_and_parse_arguments(tool, arguments)
    # Parse JSON arguments
    begin
      args = JSON.parse(arguments)
    rescue JSON::ParserError
      # If invalid, try repairing the JSON
      begin
        Rails.logger.debug "Invalid JSON in tool arguments, attempting to repair: #{arguments}"
        repaired_arguments = JSON.repair(arguments)
        args = JSON.parse(repaired_arguments)
        Rails.logger.debug "Repaired JSON: #{args}"
      rescue JSON::ParserError
        raise ToolExecutionError, "Invalid JSON in tool arguments, unable to repair"
      end
    end

    # Get required parameters from tool specifications
    required_params = tool.specifications["parameters"]["required"]

    # Check all required parameters are present
    missing_params = required_params - args.keys
    unless missing_params.empty?
      raise ToolExecutionError, "Missing required parameters: #{missing_params.join(', ')}"
    end

    # Validate argument types if specified in the tool
    tool.specifications["parameters"]["properties"].each do |param_name, param_spec|
      next unless args.key?(param_name)

      case param_spec["type"]
      when "string"
        unless args[param_name].is_a?(String)
          raise ToolExecutionError, "Parameter '#{param_name}' must be a string"
        end
      when "array"
        unless args[param_name].is_a?(Array)
          raise ToolExecutionError, "Parameter '#{param_name}' must be an array"
        end
        # Add more type validations as needed
      end
    end
    # Return the validated and parsed arguments
    args
  end

  def execute_chalkboard_url(args)
    Rails.logger.debug "Broadcasting URL to chalkboard #{args["url"]}"

    # Broadcast chalkboard update to the conversation
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{@conversation.id}",
      target: "chalkboard",
      partial: "shared/chalkboard_iframe",
      locals: { url: args["url"] }
    )
  end

  def execute_complete_lesson(args)
    # Get the current lesson from the conversation
    student = @conversation.user
    lesson_progress = @conversation.lesson_progress
    lesson = lesson_progress.lesson

    raise ToolExecutionError, "No active lesson found for this conversation" unless lesson
    raise ToolExecutionError, "No student found for this conversation" unless student

    # Create the student report
    StudentReport.create!(
      student: student,
      teacher: lesson.teacher,
      reportable: lesson_progress, # Associate the report with the LessonProgress, which will cause lesson_progress.completed? to return true
      progress_data: args,
      author_type: :ai_generated,
      status: :completed
    )

    Rails.logger.debug("Lesson completed and student report generated for lesson: #{lesson.id}, student: #{student.id}")
    Rails.logger.debug("Report: #{args}")

    # Broadcast completion message to the conversation
    @message.update(content: @message.content + "\n<br><span class='text-white bg-green-600 p-2 rounded-sm'><b>Lesson completed!<b> You can close the tab.</span>")
  end

  def execute_chalkboard_file(args)
    resource_id = args["resource_id"]

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
  end

  def execute_python_code_executor(args, tool_call_id)
    code = args["code"]
    result = PythonCodeExecutorService.execute(code)
    if result["error"]
      content = "Python execution failed: #{result["error"]}"
      Rails.logger.error("PythonCodeExecutorService error: #{result["error"]}")
    else
      content = result.to_s
      Rails.logger.debug "PythonCodeExecutorService output: #{content}"
    end
    Message.create!(
      conversation: @conversation,
      role: "tool",
      content: content,
      tool_call_id: tool_call_id
    )
    GetLlmCompletionJob.perform_later(conversation: @conversation) # Concurrency control is in place, so the original job will finish first.
  end

  def broadcast_error(message, conversation)
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{@conversation.id}",
      target: "flash_bar",
      partial: "shared/flash",
      locals: { flash: { error: message } }
    )
  end
end
