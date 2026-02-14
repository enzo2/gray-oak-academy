require "json/repair"
require "digest"

class ResponsesFunctionCallAdapter
  EXA_TOOL_NAMES = %w[exa_websearch exa_answer].freeze
  EXA_WEBSEARCH_NUM_RESULTS = 10
  EXA_WEBSEARCH_HIGHLIGHT_MAX_CHARS = 2_000

  def initialize(current_user:, conversation: nil, message: nil, exa_enabled: false, allow_app_tools: true)
    @current_user = current_user
    @conversation = conversation
    @message = message
    @exa_enabled = exa_enabled
    @allow_app_tools = allow_app_tools
  end

  def delegate_provider_native_tools
    return [] if @exa_enabled
    [ { type: "web_search" } ]
  end

  def delegate_flow_tools
    return [] unless @exa_enabled
    exa_tools
  end

  def conversation_flow_tools
    return [] unless @exa_enabled
    exa_tools
  end

  def function_calls(response_hash)
    Array(response_hash["output"]).select { |item| item["type"].to_s == "function_call" }
  end

  def function_call_outputs(function_calls)
    Array(function_calls).map { |function_call| execute_function_call(function_call) }
  end

  def function_calls_as_chat_tool_calls(function_calls)
    Array(function_calls).map do |function_call|
      call_id = function_call["call_id"] || function_call["id"]
      tool_call = {
        "type" => "function",
        "id" => call_id,
        "function" => {
          "name" => function_call["name"].to_s,
          "arguments" => function_call["arguments"].to_s
        }
      }
      response_item_id = function_call["id"]
      tool_call["response_item_id"] = response_item_id if response_item_id.present?
      tool_call
    end
  end

  private

  def exa_tools
    [ exa_websearch_tool, exa_answer_tool ]
  end

  def exa_websearch_tool
    {
      type: "function",
      name: "exa_websearch",
      description: "Use Exa web search and return grounded sources.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Web query to search with Exa." }
        },
        required: [ "query" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def exa_answer_tool
    {
      type: "function",
      name: "exa_answer",
      description: "Use Exa answer endpoint for a grounded answer.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Question to answer using Exa." }
        },
        required: [ "query" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def execute_function_call(function_call)
    call_id = (function_call["call_id"] || function_call["id"]).to_s
    raise OpenAiError, "Function call is missing call_id." if call_id.blank?

    name = function_call["name"].to_s
    output =
      if EXA_TOOL_NAMES.include?(name)
        execute_exa_tool_call(name, function_call)
      else
        execute_app_tool_call(name, function_call, call_id)
      end

    {
      id: "fco_#{Digest::SHA256.hexdigest("#{call_id}:#{output}")[0, 24]}",
      type: "function_call_output",
      call_id: call_id,
      output: output.to_s
    }
  end

  def execute_exa_tool_call(name, function_call)
    raise OpenAiError, "Exa tool calls are not enabled." unless @exa_enabled

    args = parse_function_call_arguments(function_call)
    query = args["query"].to_s.strip
    raise OpenAiError, "Exa tool call is missing required query argument." if query.blank?

    case name
    when "exa_websearch"
      exa_service.search(
        query: query,
        numResults: EXA_WEBSEARCH_NUM_RESULTS,
        contents: {
          text: false,
          highlights: {
            maxCharacters: EXA_WEBSEARCH_HIGHLIGHT_MAX_CHARS
          }
        }
      ).to_json
    when "exa_answer"
      exa_service.answer(query: query).to_json
    else
      raise OpenAiError, "Unsupported Exa tool call: #{name}"
    end
  end

  def execute_app_tool_call(name, function_call, call_id)
    raise OpenAiError, "App tool calls require an active conversation." if @conversation.blank?
    raise OpenAiError, "Tool execution is disabled for this adapter." unless @allow_app_tools

    tool_message = tool_execution_service.execute_tool_call(
      id: call_id,
      name: name,
      arguments: function_call["arguments"].presence || "{}"
    )

    content = tool_message&.content
    content ||= @conversation.messages.where(role: "tool", tool_call_id: call_id).reorder(created_at: :desc).pick(:content)
    content.presence || "Tool execution completed."
  end

  def parse_function_call_arguments(function_call)
    raw_arguments = function_call["arguments"].presence || "{}"
    JSON.parse(raw_arguments)
  rescue JSON::ParserError
    repaired = JSON.repair(raw_arguments)
    JSON.parse(repaired)
  rescue JSON::ParserError, JSON::JSONRepairError
    raise OpenAiError, "Function call arguments must be valid JSON."
  end

  def exa_service
    @exa_service ||= ExaApiService.new(
      current_user: @current_user,
      conversation: @conversation
    )
  end

  def tool_execution_service
    @tool_execution_service ||= ToolExecutionService.new(
      conversation: @conversation,
      message: @message
    )
  end
end
