require "json/repair"

class CourseResearchToolExecutor
  ToolExecutionError = ToolExecutionService::ToolExecutionError

  def initialize(course:, current_user:)
    @course = course
    @teacher = current_user
  end

  def tool_definitions
    [
      get_course_state_tool,
      apply_course_research_update_tool,
      update_outline_research_tool
    ]
  end

  def execute(function_call)
    call_id = (function_call["call_id"] || function_call["id"]).to_s
    name = function_call["name"].to_s
    args = parse_arguments(function_call["arguments"])
    output = dispatch(name, args)

    {
      type: "function_call_output",
      call_id: call_id.presence || "unknown_call",
      output: output.is_a?(String) ? output : JSON.pretty_generate(output)
    }
  rescue ToolExecutionError => e
    {
      type: "function_call_output",
      call_id: call_id.presence || "unknown_call",
      output: "Tool execution error: #{e.message}"
    }
  rescue StandardError => e
    {
      type: "function_call_output",
      call_id: call_id.presence || "unknown_call",
      output: "Tool execution error: #{e.message}"
    }
  end

  private

  def dispatch(name, args)
    case name
    when "get_course_state"
      execute_get_course_state
    when "apply_course_research_update"
      execute_apply_course_research_update(args)
    when "update_outline_research"
      execute_update_outline_research(args)
    else
      raise ToolExecutionError, "Unsupported tool: #{name}"
    end
  end

  def parse_arguments(raw_arguments)
    raw = raw_arguments.presence || "{}"
    JSON.parse(raw)
  rescue JSON::ParserError
    repaired = JSON.repair(raw)
    JSON.parse(repaired)
  rescue JSON::ParserError, JSON::JSONRepairError
    raise ToolExecutionError, "Function call arguments must be valid JSON."
  end

  def execute_get_course_state
    @course.reload
    {
      course: {
        id: @course.id,
        title: @course.title,
        summary: @course.summary,
        grade_level: @course.grade_level,
        outline: @course.outline,
        outline_guidance_report_md: @course.outline_guidance_report_md,
        outline_research: @course.outline_research
      }
    }
  end

  def execute_apply_course_research_update(args)
    summary = args["summary"]
    outline = args["outline"]
    outline_guidance_report_md = args["outline_guidance_report_md"]
    outline_research = args["outline_research"]

    attrs = {}
    attrs[:summary] = summary.to_s if summary.is_a?(String)
    attrs[:outline] = normalize_outline(outline) if outline.is_a?(Array)
    attrs[:outline_guidance_report_md] = outline_guidance_report_md.to_s if outline_guidance_report_md.is_a?(String)
    attrs[:outline_research] = normalize_outline_research(outline_research) if outline_research.is_a?(Hash)

    if attrs.empty?
      raise ToolExecutionError, "No updatable fields were provided. Provide at least one of summary, outline, outline_guidance_report_md, or outline_research."
    end

    UndoCourseResearchChangesService.new(course: @course).capture_prior_state!
    @course.update!(attrs)
    execute_get_course_state
  end

  def execute_update_outline_research(args)
    patch = args["outline_research_patch"]
    raise ToolExecutionError, "outline_research_patch must be an object." unless patch.is_a?(Hash)
    patch = sanitize_outline_research_patch(patch)
    raise ToolExecutionError, "outline_research_patch did not include any fields to update." if patch.blank?

    current = @course.outline_research.is_a?(Hash) ? @course.outline_research.deep_dup : {}
    merged = current.deep_merge(patch)
    merged = normalize_outline_research(merged)

    UndoCourseResearchChangesService.new(course: @course).capture_prior_state!
    @course.update!(outline_research: merged)
    execute_get_course_state
  end

  def normalize_outline_research(value)
    normalized = value.deep_dup
    source_anchors = Array(normalized["source_anchors"]).map.with_index do |anchor, idx|
      next {} unless anchor.is_a?(Hash)

      {
        "id" => anchor["id"].presence || "anchor_#{idx + 1}",
        "title" => anchor["title"].to_s,
        "url" => anchor["url"].to_s,
        "excerpt" => anchor["excerpt"].to_s,
        "highlights" => Array(anchor["highlights"]).map(&:to_s),
        "notes" => anchor["notes"].to_s
      }
    end

    normalized["source_anchors"] = source_anchors
    normalized["coverage_gaps"] = Array(normalized["coverage_gaps"]).map(&:to_s)
    normalized["factual_notes"] = Array(normalized["factual_notes"]).map(&:to_s)
    normalized["alternative_approaches"] = Array(normalized["alternative_approaches"]).map(&:to_s)
    normalized
  end

  def sanitize_outline_research_patch(patch)
    allowed_keys = %w[source_anchors coverage_gaps factual_notes alternative_approaches]
    patch.to_h.each_with_object({}) do |(key, value), memo|
      normalized_key = key.to_s
      next unless allowed_keys.include?(normalized_key)
      next if value.nil?

      memo[normalized_key] = value
    end
  end

  def normalize_outline(outline_items)
    outline_items.map do |item|
      unless item.is_a?(Hash)
        raise ToolExecutionError, "Each outline item must be an object with topic and description."
      end

      topic = item["topic"].to_s
      description = item["description"].to_s
      if topic.blank? || description.blank?
        raise ToolExecutionError, "Each outline item must include non-empty topic and description."
      end

      { topic => description }
    end
  end

  def get_course_state_tool
    {
      type: "function",
      name: "get_course_state",
      description: "Read the latest persisted course summary, outline, guidance report markdown, and normalized outline_research payload before making changes.",
      parameters: {
        type: "object",
        properties: {},
        required: [],
        additionalProperties: false
      },
      strict: true
    }
  end

  def apply_course_research_update_tool
    {
      type: "function",
      name: "apply_course_research_update",
      description: "Atomically apply teacher-approved course updates. This schema is strict, so all four top-level keys must be present; pass null for any field you do not want to change.",
      parameters: {
        type: "object",
        properties: {
          summary: {
            type: [ "string", "null" ],
            description: "Complete replacement course summary. Pass null to leave the current summary unchanged."
          },
          outline: {
            type: [ "array", "null" ],
            description: "Complete replacement course outline. Each item must contain a topic and description. Pass null to leave the current outline unchanged.",
            items: {
              type: "object",
              properties: {
                topic: { type: "string" },
                description: { type: "string" }
              },
              required: [ "topic", "description" ],
              additionalProperties: false
            }
          },
          outline_guidance_report_md: {
            type: [ "string", "null" ],
            description: "Complete replacement teacher-facing guidance report in markdown. Pass null to leave the current report unchanged."
          },
          outline_research: outline_research_schema(nullable: true)
        },
        required: %w[summary outline outline_guidance_report_md outline_research],
        additionalProperties: false
      },
      strict: true
    }
  end

  def update_outline_research_tool
    {
      type: "function",
      name: "update_outline_research",
      description: "Merge a partial patch into outline_research. Provide only the sections that should change; omitted keys are preserved.",
      parameters: {
        type: "object",
        properties: {
          outline_research_patch: outline_research_schema(nullable: false)
        },
        required: [ "outline_research_patch" ],
        additionalProperties: false
      },
      strict: true
    }
  end

  def outline_research_schema(nullable:)
    schema = {
      type: "object",
      description: "Structured research findings for teacher review. Strings may include short markdown. Arrays replace the entire existing list for that field.",
      properties: {
        source_anchors: {
          type: [ "array", "null" ],
          description: "High-quality source anchors relevant to course planning. Pass null only in apply_course_research_update to leave this field unchanged.",
          items: {
            type: "object",
            description: "A single source anchor with normalized fields for display and later teacher review.",
            properties: {
              id: {
                type: [ "string", "null" ],
                description: "Stable anchor identifier. Reuse an existing id when updating an existing anchor."
              },
              title: {
                type: [ "string", "null" ],
                description: "Teacher-facing title of the source."
              },
              url: {
                type: [ "string", "null" ],
                description: "Canonical source URL."
              },
              excerpt: {
                type: [ "string", "null" ],
                description: "Short excerpt or synopsis of the source. Markdown is allowed."
              },
              highlights: {
                type: [ "array", "null" ],
                description: "Short bullet-style highlights extracted from the source. Markdown is allowed in each string.",
                items: { type: [ "string", "null" ] }
              },
              notes: {
                type: [ "string", "null" ],
                description: "Brief note about why the source matters for this course. Markdown is allowed."
              }
            },
            required: %w[id title url excerpt highlights notes],
            additionalProperties: false
          }
        },
        coverage_gaps: {
          type: [ "array", "null" ],
          description: "Important topics missing from the outline. Pass null only in apply_course_research_update to leave unchanged.",
          items: { type: [ "string", "null" ] }
        },
        factual_notes: {
          type: [ "array", "null" ],
          description: "Accuracy caveats, corrections, or clarifications that matter for planning. Pass null only in apply_course_research_update to leave unchanged.",
          items: { type: [ "string", "null" ] }
        },
        alternative_approaches: {
          type: [ "array", "null" ],
          description: "Alternative sequencing, framing, or pedagogical approaches. Pass null only in apply_course_research_update to leave unchanged.",
          items: { type: [ "string", "null" ] }
        }
      },
      required: %w[source_anchors coverage_gaps factual_notes alternative_approaches],
      additionalProperties: false
    }
    schema[:type] = [ "object", "null" ] if nullable
    schema
  end
end
