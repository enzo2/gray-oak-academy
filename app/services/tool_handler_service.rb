class ToolHandlerService
  class ToolExecutionError < StandardError; end

  def initialize(conversation:)
    @conversation = conversation
  end

  def execute_tool_call(tool_call)
    # Find the tool by name
    tool = Tool.find_by(name: tool_call[:name])
    raise ToolExecutionError, "Tool '#{tool_call[:name]}' not found" unless tool

    # Validate arguments against tool specifications
    validate_arguments(tool, tool_call[:arguments])

    # Execute the tool based on its name
    case tool.name
    when "Chalkboard_URL"
      execute_chalkboard_url(tool_call[:arguments])
    else
      raise ToolExecutionError, "Tool '#{tool.name}' execution not implemented"
    end
  end

  private

  def validate_arguments(tool, arguments)
    # Parse JSON arguments
    begin
      args = JSON.parse(arguments)
    rescue JSON::ParserError
      raise ToolExecutionError, "Invalid JSON in tool arguments"
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
        # Add more type validations as needed
      end
    end
  end

  def execute_chalkboard_url(arguments)
    args = JSON.parse(arguments)

    Rails.logger.debug "Broadcasting URL to chalkboard #{args["url"]}"

    # Broadcast chalkboard update to the conversation
    Turbo::StreamsChannel.broadcast_update_to(
      "conversation_#{@conversation.id}",
      target: "chalkboard",
      partial: "shared/chalkboard_iframe",
      locals: { url: args["url"] }
    )

    Rails.logger.debug("Chalkboard updated with URL: #{args['url']}")
  end
end
