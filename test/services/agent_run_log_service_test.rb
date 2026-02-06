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
    assert_equal 1, run[:assistant_turns]
    assert_equal 1, run[:tool_call_count]
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
end
