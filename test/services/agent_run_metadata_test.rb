require "test_helper"

class AgentRunMetadataTest < ActiveSupport::TestCase
  test "build normalizes ids and includes metadata version and phase" do
    metadata = AgentRunMetadata.build(
      run_id: "run_123",
      run_type: "propose_resources",
      source: "teacher_chat_tool",
      phase: "tool_turn",
      teacher_id: 42,
      lesson_plan_id: 9
    )

    assert_equal AgentRunMetadata::METADATA_VERSION, metadata[:metadata_version]
    assert_equal "run_123", metadata[:run_id]
    assert_equal "propose_resources", metadata[:run_type]
    assert_equal "teacher_chat_tool", metadata[:source]
    assert_equal "tool_turn", metadata[:phase]
    assert_equal "42", metadata[:teacher_id]
    assert_equal "9", metadata[:lesson_plan_id]
    assert_not metadata.key?(:task_preview)
  end

  test "build falls back phase and source and compacts blank values" do
    metadata = AgentRunMetadata.build(
      run_id: "run_456",
      run_type: "outline_research_apply",
      source: "",
      task_prompt: nil,
      extra: { ignored: nil, kept: "value" }
    )

    assert_equal "submitted", metadata[:phase]
    assert_equal "outline_research_apply", metadata[:source]
    assert_equal "value", metadata[:kept]
    assert_not metadata.key?(:task_prompt)
    assert_not metadata.key?(:ignored)
  end
end
