require "json/repair"
require "digest"

class ResponsesFunctionCallAdapter
  include ResponsesFunctionCalls

  EXA_TOOL_NAMES = %w[exa_websearch exa_answer].freeze
  EXA_WEBSEARCH_NUM_RESULTS = 10
  EXA_WEBSEARCH_HIGHLIGHT_MAX_CHARS = 2_000
  IMAGE_INPUT_UNSUPPORTED_SUFFIX = "The current chat model does not support image input, so it cannot inspect the generated image.".freeze

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
    select_valid_function_calls(response_hash, log_label: self.class.name)
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
      id: "fco_#{Digest::SHA256.hexdigest("#{call_id}:#{function_call_output_digest(output)}")[0, 24]}",
      type: "function_call_output",
      call_id: call_id,
      output: output
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

    result = tool_execution_service.execute_tool_call(
      id: call_id,
      name: name,
      arguments: function_call["arguments"].presence || "{}"
    )

    tool_message = tool_message_from_result(result) || latest_tool_message(call_id)
    return function_call_output_for_tool_message(tool_message) if tool_message

    content = result.content if result.respond_to?(:content)
    content.presence || "Tool execution completed."
  end

  def function_call_output_for_tool_message(tool_message)
    content = tool_message.content.to_s.presence || "Tool execution completed."
    return content if tool_message.images.blank?

    if (invisible_reason = generated_image_invisible_reason)
      return [ content, invisible_reason ].join(" ")
    end

    image_items = image_function_call_output_items(tool_message)
    return content if image_items.blank?

    [
      { "type" => "input_text", "text" => content },
      *image_items
    ]
  end

  def image_function_call_output_items(tool_message)
    tool_message.images.filter_map do |image|
      image_url = image.image_for_LLM
      next if image_url.blank?

      { "type" => "input_image", "image_url" => image_url, "detail" => "auto" }
    rescue StandardError => e
      Rails.logger.error("Failed to serialize generated image for Responses tool output: #{e.message}")
      nil
    end
  end

  def generated_image_invisible_reason
    return IMAGE_INPUT_UNSUPPORTED_SUFFIX unless @conversation&.image_input_supported?

    nil
  end

  def tool_message_from_result(result)
    return result if result.respond_to?(:role_tool?) && result.role_tool?

    nil
  end

  def latest_tool_message(call_id)
    @conversation.messages.where(role: "tool", tool_call_id: call_id).reorder(created_at: :desc, id: :desc).first
  end

  def function_call_output_digest(output)
    return output if output.is_a?(String)

    JSON.generate(output)
  rescue StandardError
    output.to_s
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
