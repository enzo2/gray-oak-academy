require "test_helper"

class AgentRunLogServiceTest < ActiveSupport::TestCase
  def setup
    @app_setting = AppSetting.first
    @app_setting.update!(log: @app_setting.log.merge("agent_run_logs" => []))
    @service = AgentRunLogService.new(app_setting: @app_setting)
    @teacher = users(:admin)
  end

  test "records submitted and completed run with metrics" do
    @service.record_submitted(
      run_id: "run_1",
      response_id: "resp_1",
      teacher: @teacher,
      model: "gpt-5.2",
      source: "tool_call",
      prompt: "Build a thing"
    )

    response_hash = {
      "output" => [
        { "type" => "reasoning" },
        { "type" => "function_call" },
        { "type" => "message", "role" => "assistant" }
      ]
    }
    @service.record_completed(
      run_id: "run_1",
      response_id: "resp_1",
      response_hash: response_hash,
      started_at: 2.seconds.ago
    )

    run = @service.list.first
    assert_equal "run_1", run[:run_id]
    assert_equal "resp_1", run[:response_id]
    assert_equal "completed", run[:status]
    assert_equal "Build a thing", run[:task_prompt]
    assert_equal 1, run[:assistant_turns]
    assert_equal 1, run[:tool_call_count]
    assert_equal 1, run[:tool_turn_count]
    assert_equal 1, run[:reasoning_item_count]
    assert_equal 3, run[:output_item_count]
    assert run[:duration_seconds].to_f >= 0
  end

  test "records failed run with error message" do
    @service.record_failed(
      run_id: "run_2",
      response_id: "resp_2",
      response_hash: {},
      started_at: 1.second.ago,
      error_message: "Something failed"
    )

    run = @service.list.first
    assert_equal "failed", run[:status]
    assert_equal "Something failed", run[:error_message]
  end

  test "uses provided metrics when recording completed run" do
    @service.record_submitted(
      run_id: "run_3",
      response_id: "resp_3",
      teacher: @teacher,
      model: "gpt-5.2",
      source: "propose_resources",
      prompt: "Build resources"
    )

    @service.record_completed(
      run_id: "run_3",
      response_id: "resp_3",
      response_hash: { "output" => [] },
      started_at: 2.seconds.ago,
      metrics: {
        assistant_turns: 4,
        tool_call_count: 7,
        tool_turn_count: 2,
        reasoning_item_count: 3,
        output_item_count: 14
      },
      tool_calls: [
        {
          response_id: "resp_turn_1",
          call_id: "call_1",
          name: "exa_search",
          arguments_preview: "query=refraction physics",
          argument_fingerprint: "fingerprint-1"
        },
        {
          response_id: "resp_turn_2",
          call_id: "call_2",
          name: "exa_get_contents",
          arguments_preview: "urls=2 first=https://example.com/article",
          argument_fingerprint: "fingerprint-2"
        }
      ]
    )

    run = @service.list.first
    assert_equal 4, run[:assistant_turns]
    assert_equal 7, run[:tool_call_count]
    assert_equal 2, run[:tool_turn_count]
    assert_equal 3, run[:reasoning_item_count]
    assert_equal 14, run[:output_item_count]
    assert_equal "resp_turn_1", run[:tool_calls][0][:response_id]
    assert_equal "call_1", run[:tool_calls][0][:call_id]
    assert_equal "exa_search", run[:tool_calls][0][:name]
    assert_equal "query=refraction physics", run[:tool_calls][0][:arguments_preview]
    assert_equal "fingerprint-1", run[:tool_calls][0][:argument_fingerprint]
    assert_equal "resp_turn_2", run[:tool_calls][1][:response_id]
    assert_equal "call_2", run[:tool_calls][1][:call_id]
    assert_equal "exa_get_contents", run[:tool_calls][1][:name]
    assert_equal "urls=2 first=https://example.com/article", run[:tool_calls][1][:arguments_preview]
    assert_equal "fingerprint-2", run[:tool_calls][1][:argument_fingerprint]
  end
end
