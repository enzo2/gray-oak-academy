class AgentRunMetadata
  METADATA_VERSION = "1".freeze

  def self.build(run_id:, run_type:, source:, phase: "submitted", task_prompt: nil, retry_reason: nil, teacher_id: nil, lesson_plan_id: nil, course_id: nil, extra: nil)
    metadata = {
      metadata_version: METADATA_VERSION,
      run_id: run_id.to_s.presence,
      run_type: run_type.to_s.presence,
      source: source.to_s.presence || run_type.to_s.presence,
      phase: phase.to_s.presence || "submitted",
      task_prompt: task_prompt,
      retry_reason: retry_reason,
      teacher_id: teacher_id.to_s.presence,
      lesson_plan_id: lesson_plan_id.to_s.presence,
      course_id: course_id.to_s.presence
    }.compact

    if extra.is_a?(Hash)
      metadata.merge!(extra.compact)
    end

    metadata
  end
end
