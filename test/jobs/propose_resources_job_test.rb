require "test_helper"

class ProposeResourcesJobTest < ActiveSupport::TestCase
  test "propose resources updates suggested_resources from responses output" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    app_setting = AppSetting.settings
    app_setting.update!(background_agent_model: "gpt-5.2", background_agent_supported_api_id: supported_apis(:openai).id)

    complete_calls = []
    wait_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      { "id" => "resp_1", "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      wait_calls << { response_id: response_id, kwargs: kwargs }
      {
        "id" => "resp_1",
        "status" => "completed",
        "output" => [
          {
            "type" => "message",
            "content" => [
              {
                "type" => "output_text",
                "text" => "{\"suggested_resources\":[{\"type\":\"Video\",\"description\":\"NASA refraction demonstration video\"}]}"
              }
            ]
          }
        ]
      }
    end
    fake_client.define_singleton_method(:output_text) do |_response_hash|
      "{\"suggested_resources\":[{\"type\":\"Video\",\"description\":\"NASA refraction demonstration video\"}]}"
    end

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    captured_new_kwargs = nil

    OpenaiResponsesService.stub(:for_agent_run, ->(**kwargs) { captured_new_kwargs = kwargs; fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          ProposeResourcesJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id, source: "teacher_chat_tool")
        end
      end
    end

    lesson_plan.reload
    assert_equal "completed", lesson_plan.generation_stage
    assert_equal "NASA refraction demonstration video", lesson_plan.suggested_resources.first["Video"]
    assert_equal teacher, captured_new_kwargs[:user]
    assert_nil captured_new_kwargs[:base_uri]
    assert_nil captured_new_kwargs[:access_token]
    assert_nil captured_new_kwargs[:model]
    assert_equal "propose_resources", complete_calls.first.dig(:kwargs, :metadata, :run_type)
    assert_equal true, complete_calls.first.dig(:kwargs, :background)
    assert_equal teacher.id.to_s, complete_calls.first.dig(:kwargs, :metadata, :teacher_id)
    assert_equal lesson_plan.id.to_s, complete_calls.first.dig(:kwargs, :metadata, :lesson_plan_id)
    assert_equal "teacher_chat_tool", complete_calls.first.dig(:kwargs, :metadata, :source)
    assert_nil complete_calls.first.dig(:kwargs, :metadata, :task_preview)
    assert_nil complete_calls.first.dig(:kwargs, :metadata, :task_full)
    assert_equal "resp_1", wait_calls.first[:response_id]
  end

  test "propose resources automatically reverts published lesson plan to draft" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    lesson_plan.update!(content: [ { "Intro" => "Ready" } ], status: "published")
    app_setting = AppSetting.settings
    app_setting.update!(background_agent_model: "gpt-5.2")

    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |_messages = nil, **_kwargs|
      { "id" => "resp_1", "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |_response_id, **_kwargs|
      {
        "id" => "resp_1",
        "status" => "completed",
        "output" => [
          {
            "type" => "message",
            "content" => [
              { "type" => "output_text", "text" => "{\"suggested_resources\":[]}" }
            ]
          }
        ]
      }
    end
    fake_client.define_singleton_method(:output_text) { |_response_hash| "{\"suggested_resources\":[]}" }

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          ProposeResourcesJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id, source: "teacher_chat_tool")
        end
      end
    end

    assert_equal "draft", lesson_plan.reload.status
  end

  test "propose resources requests a retry turn after any tool execution error" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    app_setting = AppSetting.settings
    app_setting.update!(background_agent_model: "gpt-5.2", background_agent_supported_api_id: supported_apis(:openai).id)

    complete_calls = []
    wait_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      response_id = "resp_#{complete_calls.size}"
      { "id" => response_id, "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      wait_calls << { response_id: response_id, kwargs: kwargs }
      case response_id
      when "resp_1"
        {
          "id" => "resp_1",
          "status" => "completed",
          "output" => [
            {
              "type" => "function_call",
              "name" => "add_and_link_resource",
              "call_id" => "call_90147326",
              "arguments" => {
                resource_type: "applet",
                category: "interactive-diagram",
                description: "Jazz fusion signal chain",
                applet_title: "Signal Chain Explorer",
                applet_code: "function broken( {"
              }.to_json
            }
          ]
        }
      when "resp_2"
        {
          "id" => "resp_2",
          "status" => "completed",
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "{\"suggested_resources\":[]}" }
              ]
            }
          ]
        }
      else
        {
          "id" => "resp_3",
          "status" => "completed",
          "output" => [
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => "{\"suggested_resources\":[{\"type\":\"Applet\",\"description\":\"Interactive jazz fusion signal chain applet\"}]}"
                }
              ]
            }
          ]
        }
      end
    end
    fake_client.define_singleton_method(:output_text) do |response_hash|
      Array(response_hash["output"]).flat_map do |item|
        next [] unless item["type"] == "message"
        Array(item["content"]).filter_map { |part| part["text"] if part["type"] == "output_text" }
      end.join("\n")
    end

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:execute) do |_function_call|
      {
        type: "function_call_output",
        call_id: "call_90147326",
        output: "Tool execution error: image_token is missing or invalid."
      }
    end
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          ProposeResourcesJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id, source: "teacher_chat_tool")
        end
      end
    end

    assert_equal 3, complete_calls.size
    assert_equal "resp_1", wait_calls.first[:response_id]
    assert_equal "resp_2", wait_calls.second[:response_id]
    assert_equal "resp_3", wait_calls.third[:response_id]

    retry_call = complete_calls.third
    assert_equal "resp_2", retry_call.dig(:kwargs, :previous_response_id)
    assert_includes retry_call.dig(:messages, 0, :content), "One or more tool calls failed"
    assert_includes retry_call.dig(:messages, 0, :content), "image_token is missing or invalid"

    assert_equal "completed", lesson_plan.reload.generation_stage
    assert_equal "Interactive jazz fusion signal chain applet", lesson_plan.suggested_resources.first["Applet"]
  end

  test "propose resources notifies superusers when high tool-call threshold is reached" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    superuser = users(:super_user)
    superuser.create_setting! if superuser.setting.nil?
    app_setting = AppSetting.settings
    app_setting.update!(background_agent_model: "gpt-5.2")

    tool_calls = Array.new(ProposeResourcesJob::HIGH_TOOL_CALL_WARNING_THRESHOLD + 3) do |idx|
      {
        "type" => "function_call",
        "name" => "exa_search",
        "call_id" => "call_#{idx + 1}",
        "arguments" => { query: "query #{idx + 1}" }.to_json
      }
    end

    complete_calls = []
    wait_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      response_id = complete_calls.size == 1 ? "resp_1" : "resp_2"
      { "id" => response_id, "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **kwargs|
      wait_calls << { response_id: response_id, kwargs: kwargs }
      case response_id
      when "resp_1"
        { "id" => "resp_1", "status" => "completed", "output" => tool_calls }
      else
        {
          "id" => "resp_2",
          "status" => "completed",
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "output_text", "text" => "{\"suggested_resources\":[]}" }
              ]
            }
          ]
        }
      end
    end
    fake_client.define_singleton_method(:output_text) { |_response_hash| "{\"suggested_resources\":[]}" }

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:execute) do |function_call|
      { type: "function_call_output", call_id: function_call["call_id"], output: "{\"ok\":true}" }
    end
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    app_setting.update!(log: (app_setting.log || {}).merge("analytics_events" => []))
    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          ProposeResourcesJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id, source: "teacher_chat_tool")
        end
      end
    end

    assert_equal "resp_1", wait_calls.first[:response_id]
    assert_equal "resp_2", wait_calls.second[:response_id]

    warning_notifications = Notification.where(event_type: "agent_run.high_tool_call_warning", recipient_id: superuser.id)
    assert_equal 1, warning_notifications.count
    warning_notification = warning_notifications.first
    assert_equal "resp_1", warning_notification.params["run_id"]
    assert_equal "resp_1", warning_notification.params["response_id"]
    assert_equal teacher.name, warning_notification.params["teacher_name"]
    assert_equal teacher.id, warning_notification.params["teacher_id"]
    assert_equal "teacher_chat_tool", warning_notification.params["source"]
    assert_equal lesson_plan.id, warning_notification.params["lesson_plan_id"]
    assert_equal 1, warning_notification.params["turns"]
    assert_equal ProposeResourcesJob::HIGH_TOOL_CALL_WARNING_THRESHOLD + 3, warning_notification.params["total_tool_calls"]
    assert_equal ProposeResourcesJob::HIGH_TOOL_CALL_WARNING_THRESHOLD, warning_notification.params["warning_threshold"]

    analytics_events = Array(app_setting.reload.log["analytics_events"])
    analytics_warning_events = analytics_events.select { |entry| entry["event_type"] == "agent_run.high_tool_call_warning" }
    assert_equal 1, analytics_warning_events.size
  end

  test "propose resources marks the agent run failed when tool-turn limit is exceeded" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    app_setting = AppSetting.settings
    app_setting.update!(background_agent_model: "gpt-5.2", background_agent_max_tool_turns: "1")

    complete_calls = 0
    failure_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:complete) do |_messages = nil, **_kwargs|
      complete_calls += 1
      { "id" => "resp_#{complete_calls}", "status" => "queued", "output" => [] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **_kwargs|
      {
        "id" => response_id,
        "status" => "completed",
        "output" => [
          {
            "type" => "function_call",
            "name" => "exa_search",
            "call_id" => "call_#{response_id}",
            "arguments" => { query: "resource #{response_id}" }.to_json
          }
        ]
      }
    end
    fake_client.define_singleton_method(:mark_current_agent_run_failed) do |error_message:, response_hash:|
      failure_calls << { error_message: error_message, response_hash: response_hash }
    end

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:execute) do |function_call|
      { type: "function_call_output", call_id: function_call["call_id"], output: "{\"ok\":true}" }
    end
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          result = ProposeResourcesJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id, source: "teacher_chat_tool")
          assert_equal false, result
        end
      end
    end

    assert_equal "failed", lesson_plan.reload.generation_stage
    assert_equal 1, failure_calls.size
    assert_includes failure_calls.first[:error_message], "Resource proposal exceeded tool-call limit (1)"
    assert_equal "resp_2", failure_calls.first[:response_hash]["id"]
  end

  test "stateless provider replays native response items and tool outputs" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    AppSetting.settings.update!(background_agent_model: "anthropic/claude-sonnet-4.6")
    responses = [
      {
        "id" => "resp_stateless_1", "status" => "completed", "usage" => { "input_tokens" => 20 },
        "output" => [
          { "type" => "reasoning", "signature" => "signed", "format" => "anthropic-claude-v1" },
          { "type" => "function_call", "id" => "fc_1", "name" => "exa_search", "call_id" => "call_1", "arguments" => { query: "refraction" }.to_json }
        ]
      },
      {
        "id" => "resp_stateless_2", "status" => "completed", "usage" => { "input_tokens" => 40 },
        "output" => [ { "type" => "message", "content" => [ { "type" => "output_text", "text" => '{"suggested_resources":[]}' } ] } ]
      }
    ]
    complete_calls = []
    fake_client = Object.new
    fake_client.define_singleton_method(:stateful_supported?) { false }
    fake_client.define_singleton_method(:model) { "anthropic/claude-sonnet-4.6" }
    fake_client.define_singleton_method(:base_uri) { SupportedApi::OPENROUTER_BASE_URI }
    fake_client.define_singleton_method(:last_input_items) { @last_input_items.deep_dup }
    fake_client.define_singleton_method(:complete) do |messages = nil, **kwargs|
      complete_calls << { messages: messages, kwargs: kwargs }
      @last_input_items = if messages.present?
        [ { "role" => "developer", "content" => "system" }, { "role" => "user", "content" => messages.first[:content] } ]
      else
        kwargs.fetch(:input).deep_dup
      end
      { "id" => responses.fetch(complete_calls.size - 1)["id"] }
    end
    fake_client.define_singleton_method(:wait_for_response) do |response_id, **_kwargs|
      responses.find { |response| response["id"] == response_id }
    end
    fake_client.define_singleton_method(:output_text) do |response_hash|
      response_hash["id"] == "resp_stateless_2" ? '{"suggested_resources":[]}' : ""
    end
    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:execute) do |call|
      { type: "function_call_output", call_id: call["call_id"], output: '{"results":[]}' }
    end
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }
    captured_new_kwargs = nil

    OpenaiResponsesService.stub(:for_agent_run, ->(**kwargs) { captured_new_kwargs = kwargs; fake_client }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          assert ProposeResourcesJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id, source: "teacher_chat_tool")
        end
      end
    end

    assert_equal false, captured_new_kwargs[:agent_run_require_stateful]
    assert_equal 2, complete_calls.size
    assert_nil complete_calls.second[:messages]
    replay = complete_calls.second.dig(:kwargs, :input)
    assert_equal responses.first["output"], replay[2, 2]
    assert_equal "function_call_output", replay.last[:type]
    assert_nil complete_calls.second.dig(:kwargs, :previous_response_id)
  end

  test "codex usage limit re-runs on the shared provider and stays in progress" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    AppSetting.settings.update!(
      background_agent_model: "gpt-5.2",
      background_agent_supported_api_id: supported_apis(:openai).id
    )
    usage_limit_error = BackgroundAgentConfigResolver::CodexUsageLimitError.new("The usage limit has been reached")

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    enqueued = []
    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { raise usage_limit_error }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        ProposeResourcesJob.stub(:perform_later, ->(**kwargs) { enqueued << kwargs }) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            result = ProposeResourcesJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id)
            assert_equal false, result
          end
        end
      end
    end

    assert_equal 1, enqueued.size
    assert_equal true, enqueued.first[:skip_user_codex]
    assert_equal lesson_plan.id, enqueued.first[:lesson_plan_id]

    lesson_plan.reload
    assert_equal "proposing_resources", lesson_plan.generation_stage
    assert_nil lesson_plan.generation_error
  end

  test "codex usage limit without a shared provider fails the lesson plan" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    AppSetting.settings.update!(
      background_agent_model: nil,
      background_agent_supported_api_id: nil,
      background_agent_prefer_user_codex: "0"
    )
    usage_limit_error = BackgroundAgentConfigResolver::CodexUsageLimitError.new("The usage limit has been reached")

    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    enqueued = []
    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { raise usage_limit_error }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        ProposeResourcesJob.stub(:perform_later, ->(**kwargs) { enqueued << kwargs }) do
          Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
            result = ProposeResourcesJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id)
            assert_equal false, result
          end
        end
      end
    end

    assert_empty enqueued
    lesson_plan.reload
    assert_equal "failed", lesson_plan.generation_stage
    assert_includes lesson_plan.generation_error, "usage limit"
  end

  test "transient OAuth failures remain in progress until retries are exhausted" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    transient_error = BackgroundAgentConfigResolver::TransientOauthError.new("temporary OAuth failure")
    fake_executor = Object.new
    fake_executor.define_singleton_method(:tool_definitions) { [] }
    fake_executor.define_singleton_method(:cleanup_tempfiles) { true }

    OpenaiResponsesService.stub(:for_agent_run, ->(**_kwargs) { raise transient_error }) do
      ProposeResourcesToolExecutor.stub(:new, ->(**_kwargs) { fake_executor }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          job = ProposeResourcesJob.new
          assert_raises(BackgroundAgentConfigResolver::TransientOauthError) do
            job.perform(lesson_plan_id: lesson_plan.id, user_id: teacher.id)
          end

          lesson_plan.reload
          assert_equal "proposing_resources", lesson_plan.generation_stage
          assert_nil lesson_plan.generation_error

          final_job = ProposeResourcesJob.new
          final_job.executions = ProposeResourcesJob::OAUTH_RETRY_ATTEMPTS
          assert_raises(BackgroundAgentConfigResolver::TransientOauthError) do
            final_job.perform(lesson_plan_id: lesson_plan.id, user_id: teacher.id)
          end
        end
      end
    end

    lesson_plan.reload
    assert_equal "failed", lesson_plan.generation_stage
    assert_includes lesson_plan.generation_error, "temporary OAuth failure"
  end
end

class GenerateLessonPlanPipelineJobTest < ActiveSupport::TestCase
  test "pipeline runs content then resource proposal when requested" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    order = []

    captured_source = nil
    captured_track_stage = nil
    GenerateLessonPlanContentJob.stub(:perform_now, ->(*_args, **_kwargs) { order << :content }) do
      ProposeResourcesJob.stub(:perform_now, ->(**kwargs) {
        order << :resources
        captured_source = kwargs[:source]
        captured_track_stage = kwargs[:track_stage]
        lesson_plan.update!(generation_stage: "completed", generation_error: nil)
      }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          GenerateLessonPlanPipelineJob.perform_now(
            lesson_plan_id: lesson_plan.id,
            user_id: teacher.id,
            propose_resources: true,
            source: "teacher_chat_tool"
          )
        end
      end
    end

    lesson_plan.reload
    assert_equal [ :content, :resources ], order
    assert_equal "teacher_chat_tool", captured_source
    assert_equal true, captured_track_stage
    assert_equal "completed", lesson_plan.generation_stage
  end

  test "pipeline does not overwrite a detached resource proposal retry state" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)

    GenerateLessonPlanContentJob.stub(:perform_now, true) do
      ProposeResourcesJob.stub(:perform_now, ->(**) {
        lesson_plan.update!(
          generation_stage: "proposing_resources",
          generation_error: nil
        )
        true
      }) do
        Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
          GenerateLessonPlanPipelineJob.perform_now(
            lesson_plan_id: lesson_plan.id,
            user_id: teacher.id,
            propose_resources: true
          )
        end
      end
    end

    lesson_plan.reload
    assert_equal "proposing_resources", lesson_plan.generation_stage
    assert_nil lesson_plan.generation_error
  end

  test "authorization failures do not mutate another teacher's lesson plan" do
    lesson_plan = lesson_plans(:one)
    other_teacher = users(:admin2)
    lesson_plan.update!(generation_stage: "completed", generation_error: nil)

    assert_raises(ActiveRecord::RecordNotFound) do
      GenerateLessonPlanPipelineJob.perform_now(
        lesson_plan_id: lesson_plan.id,
        user_id: other_teacher.id,
        propose_resources: false
      )
    end

    lesson_plan.reload
    assert_equal "completed", lesson_plan.generation_stage
    assert_nil lesson_plan.generation_error
  end

  # Regression: a failure used to only broadcast a morph refresh, which did not
  # reliably re-render the inline generation status on the open edit page, so the
  # failure stayed hidden until a manual reload. The failure path must replace the
  # generation controls directly so "Generation failed." surfaces live.
  test "failure replaces both generation controls so neither status is stranded" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)
    replace_calls = []

    GenerateLessonPlanContentJob.stub(:perform_now, ->(*_args, **_kwargs) {
      raise OpenAiError, "Codex stream request failed: status=429 usage_limit_reached"
    }) do
      Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
        Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*_args, **kwargs) {
          replace_calls << kwargs
        }) do
          assert_raises(OpenAiError) do
            GenerateLessonPlanPipelineJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id)
          end
        end
      end
    end

    lesson_plan.reload
    assert_equal "failed", lesson_plan.generation_stage
    assert_includes lesson_plan.generation_error, "status=429"

    targets = replace_calls.map { |kwargs| kwargs[:target] }
    assert_includes targets, "lesson-plan-generation-controls"
    assert_includes targets, "resource-proposal-controls"

    generation_call = replace_calls.find { |kwargs| kwargs[:target] == "lesson-plan-generation-controls" }
    assert_equal teacher, generation_call.dig(:locals, :current_user)

    html = ApplicationController.render(
      partial: generation_call[:partial],
      locals: generation_call[:locals]
    )
    assert_includes html, "lesson-plan-generation-controls"
    assert_includes html, "Generation failed."

    # The resource-proposal control must not echo the content-generation status.
    proposal_call = replace_calls.find { |kwargs| kwargs[:target] == "resource-proposal-controls" }
    proposal_html = ApplicationController.render(
      partial: proposal_call[:partial],
      locals: proposal_call[:locals]
    )
    refute_includes proposal_html, "Generating lesson plan content"
    refute_includes proposal_html, "Generation failed."
  end

  # A per-teacher Codex usage limit must reach the inline status as parsed,
  # teacher-facing text rather than the raw "status=429 ..." provider body.
  test "codex usage limit failure renders friendly text in the generation status" do
    lesson_plan = lesson_plans(:one)
    teacher = users(:admin)

    usage_error = BackgroundAgentConfigResolver::CodexUsageLimitError.new(
      "Codex stream request failed: status=429 usage_limit_reached",
      resets_at: 90.minutes.from_now,
      plan_type: "plus"
    )

    GenerateLessonPlanContentJob.stub(:perform_now, ->(*_args, **_kwargs) { raise usage_error }) do
      Turbo::StreamsChannel.stub(:broadcast_refresh_to, true) do
        Turbo::StreamsChannel.stub(:broadcast_replace_to, true) do
          assert_raises(BackgroundAgentConfigResolver::CodexUsageLimitError) do
            GenerateLessonPlanPipelineJob.perform_now(lesson_plan_id: lesson_plan.id, user_id: teacher.id)
          end
        end
      end
    end

    lesson_plan.reload
    assert_equal "failed", lesson_plan.generation_stage
    assert_includes lesson_plan.generation_error, "ChatGPT Plus usage limit"
    assert_includes lesson_plan.generation_error, "resets in about"
    refute_includes lesson_plan.generation_error, "status=429"
    # Content generation runs on the teacher's own model, so the advice points there
    # rather than at the shared background-agent provider.
    assert_includes lesson_plan.generation_error, "Settings > LLMs"
    refute_includes lesson_plan.generation_error, "shared background-agent provider"
  end
end
