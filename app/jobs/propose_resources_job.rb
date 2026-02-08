require "json/repair"

class ProposeResourcesJob < ApplicationJob
  queue_as :default
  RESOURCES_SCHEMA = {
    type: "object",
    properties: {
      suggested_resources: {
        type: "array",
        items: {
          type: "object",
          properties: {
            type: { type: "string" },
            description: { type: "string" }
          },
          required: [ "type", "description" ],
          additionalProperties: false
        }
      }
    },
    required: [ "suggested_resources" ],
    additionalProperties: false
  }.freeze

  def perform(lesson_plan, current_user, track_stage: true, raise_on_error: false)
    lesson_plan.update!(status: "draft") if lesson_plan.status_published?

    set_generation_state(lesson_plan, "proposing_resources", nil) if track_stage
    broadcast_refresh(current_user)

    openai_config = openai_agent_config!
    prompt = build_prompt(lesson_plan, current_user)
    messages = [ { role: "user", content: prompt } ]

    executor = ProposeResourcesToolExecutor.new(lesson_plan: lesson_plan, current_user: current_user)
    client = OpenaiResponsesService.new(
      current_user: current_user,
      access_token: openai_config[:access_token],
      base_uri: openai_config[:base_uri],
      model: openai_config[:model],
      native_tools: executor.tool_definitions,
      enable_tools: false,
      reasoning_model: true,
      store: true
    )

    response_hash = complete_and_capture(
      client,
      messages: messages,
      metadata: {
        run_type: "propose_resources",
        teacher_id: current_user.id.to_s,
        lesson_plan_id: lesson_plan.id.to_s,
        source: "propose_resources",
        task_preview: "Propose resources for lesson plan #{lesson_plan.id}: #{lesson_plan.lesson.title}"
      }
    )
    max_tool_turns = AppSetting.openai_agent_max_tool_turns
    raise OpenAiError, "OpenAI agent max tool turns is not configured. Set it in App Settings." unless max_tool_turns.present?
    turns = 0

    loop do
      function_calls = Array(response_hash["output"]).select { |item| item["type"].to_s == "function_call" }
      break if function_calls.blank?

      turns += 1
      raise OpenAiError, "Resource proposal exceeded tool-call limit (#{max_tool_turns})." if turns > max_tool_turns

      outputs = function_calls.map { |fc| executor.execute(fc) }
      response_hash = complete_and_capture(
        client,
        input: outputs,
        previous_response_id: response_hash["id"],
        metadata: {
          run_type: "propose_resources",
          teacher_id: current_user.id.to_s,
          lesson_plan_id: lesson_plan.id.to_s
        }
      )
    end

    parsed = parse_output(client.output_text(response_hash))
    validate_output(parsed)
    suggested_resources = Array(parsed["suggested_resources"]).map do |item|
      { item["type"] => item["description"] }
    end

    lesson_plan.update!(
      suggested_resources: suggested_resources
    )
    set_generation_state(lesson_plan, "completed", nil) if track_stage
    broadcast_refresh(current_user)
    true
  rescue StandardError => e
    Rails.logger.error("ProposeResourcesJob failed for lesson_plan #{lesson_plan&.id}: #{e.message}")
    set_generation_state(lesson_plan, "failed", "Failed to propose resources: #{e.message}") if track_stage && lesson_plan.present?
    broadcast_refresh(current_user) if current_user.present?
    raise if raise_on_error
    false
  ensure
    executor&.cleanup_tempfiles
  end

  private

  def complete_and_capture(client, messages: nil, input: nil, previous_response_id: nil, metadata: nil)
    submitted = client.complete(
      messages,
      input: input,
      previous_response_id: previous_response_id,
      background: true,
      metadata: metadata
    )
    response_id = submitted["id"].to_s
    raise OpenAiError, "Responses API did not return a response id for background execution." if response_id.blank?

    response_hash = client.wait_for_response(
      response_id,
      timeout_seconds: 900,
      poll_interval_seconds: 2
    )
    raise OpenAiError, "Responses API did not return a valid response payload." if response_hash.blank?
    status = response_hash["status"].to_s
    if status != "completed"
      raise OpenAiError, "Responses API resource proposal run failed with status '#{status}': #{extract_response_error(response_hash)}"
    end

    response_hash
  end

  def extract_response_error(response_hash)
    error = response_hash["error"]
    return "Unknown error" if error.blank?
    return error.to_s unless error.is_a?(Hash)

    error["message"].presence || error["code"].presence || "Unknown error"
  end

  def parse_output(content)
    raise OpenAiError, "Resource proposal response was empty." if content.blank?

    code_block_json = content.scan(/```(?:json)?\s*([\s\S]*?)\s*```/i).last&.first
    match_json = content.match(/(\{[\s\S]*\}|\[[\s\S]*\])/)&.[](0)
    json_content = code_block_json.presence || match_json.presence || content.strip
    raise OpenAiError, "No JSON object found in resource proposal output." if json_content.blank?

    JSON.parse(json_content)
  rescue JSON::ParserError
    begin
      repaired = JSON.repair(json_content)
      JSON.parse(repaired)
    rescue JSON::ParserError, JSON::JSONRepairError => e
      raise OpenAiError, "Invalid JSON from resource proposal: #{e.message}"
    end
  end

  def validate_output(parsed)
    schemer = JSONSchemer.schema(RESOURCES_SCHEMA)
    return if schemer.valid?(parsed)

    errors = schemer.validate(parsed).map { |err| err["error"] }.join(", ")
    raise OpenAiError, "Invalid resource proposal schema: #{errors}"
  end

  def build_prompt(lesson_plan, current_user)
    lesson = lesson_plan.lesson
    course = lesson.course

    Prompt.get_prompt(category: "suggest_resources", user: current_user)
      .gsub("{title}", "#{lesson.position}. #{lesson.title}")
      .gsub("{goals}", lesson.goals)
      .gsub("{approx_duration_min}", lesson.approx_duration_min.to_s)
      .gsub("{grade_level}", course.grade_level)
      .gsub("{course_title}", course.title)
      .gsub("{lesson_plan_content}", lesson_plan.content.to_json)
      .gsub("{suggested_resources}", lesson_plan.suggested_resources.to_json)
      .gsub("{linked_resources}", lesson_plan.resources.format_collection)
  end

  def set_generation_state(lesson_plan, stage, error)
    lesson_plan.update!(generation_stage: stage, generation_error: error)
  end

  def openai_agent_config!
    app_setting = AppSetting.settings
    raise OpenAiError, "OpenAI Agent Runs is not configured. Ask a superuser to set the OpenAI Agent model and key in App Settings." unless app_setting&.openai_agent_enabled?

    openai_api = app_setting.openai_agent_supported_api
    raise OpenAiError, "OpenAI shared API is not configured for agent runs." unless openai_api

    {
      access_token: app_setting.openai_agent_access_token,
      base_uri: openai_api.api_base_uri,
      model: app_setting.openai_agent_model
    }
  end

  def broadcast_refresh(current_user)
    channel = "teacher_#{current_user.id}-dashboard"
    Turbo::StreamsChannel.broadcast_refresh_to(channel)
  end
end
