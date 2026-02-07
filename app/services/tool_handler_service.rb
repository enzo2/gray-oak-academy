class ToolHandlerService
  ToolExecutionError = ToolExecutionService::ToolExecutionError

  def initialize(conversation:, message:)
    @conversation = conversation
    @executor = ToolExecutionService.new(conversation: conversation, message: message)
  end

  def execute_tool_call(tool_call)
    @executor.execute_tool_call(normalize_tool_call(tool_call))
  end

  def execute_tool_calls(tool_calls)
    Array(tool_calls).each { |tool_call| execute_tool_call(tool_call) }
    GetLlmCompletionJob.perform_later(conversation: @conversation)
  end

  private

  def normalize_tool_call(tool_call)
    {
      id: tool_call[:id] || tool_call["id"] || tool_call[:call_id] || tool_call["call_id"],
      name: tool_call[:name] || tool_call["name"] || tool_call.dig(:function, :name) || tool_call.dig("function", "name"),
      arguments: tool_call[:arguments] || tool_call["arguments"] || tool_call.dig(:function, :arguments) || tool_call.dig("function", "arguments")
    }
  end

  def method_missing(method_name, *args, &block)
    return @executor.send(method_name, *args, &block) if @executor.respond_to?(method_name, true)

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    @executor.respond_to?(method_name, include_private) || super
  end
end
